//! Minimal routing and session management for NetROM leaf node
//!
//! Since tarpn-chat is a leaf node (no packet forwarding), routing is minimal:
//! - Track our single neighbor (LinBPQ)
//! - Manage L4 sessions with unique circuit IDs
//! - Track routes from NODES broadcasts to know which peers are reachable
//!
//! The SessionManager handles allocation of circuit index/id pairs and
//! provides lookup by various criteria.

use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};
use tracing::{debug, info, trace, warn};

use crate::netrom::{Callsign, NetromFrame, NodesBroadcast, L4Opcode};
use crate::session::{L4Session, SessionId, SessionState, SessionEvent};

/// Route timeout - routes expire if not refreshed
const ROUTE_TIMEOUT: Duration = Duration::from_secs(600); // 10 minutes

/// Known route from NODES broadcast
#[derive(Debug, Clone)]
pub struct Route {
    /// Destination node callsign
    pub dest_call: String,
    /// Destination alias (optional)
    pub alias: Option<String>,
    /// Quality (0-255)
    pub quality: u8,
    /// When this route was last seen
    pub last_seen: Instant,
}

/// Simple route table tracking known nodes from NODES broadcasts
pub struct RouteTable {
    /// Known routes indexed by callsign
    routes: HashMap<String, Route>,
}

impl RouteTable {
    pub fn new() -> Self {
        Self {
            routes: HashMap::new(),
        }
    }

    /// Update routes from a NODES broadcast
    pub fn update_from_nodes(&mut self, broadcast: &NodesBroadcast) {
        let now = Instant::now();

        for entry in &broadcast.routes {
            let call = entry.dest_call.to_string();
            let alias = String::from_utf8_lossy(&entry.dest_alias).trim().to_string();

            if entry.quality == 0 {
                // Quality 0 means remove route
                if self.routes.remove(&call).is_some() {
                    debug!(call = %call, "Route removed");
                }
            } else {
                let is_new = !self.routes.contains_key(&call);
                self.routes.insert(call.clone(), Route {
                    dest_call: call.clone(),
                    alias: if alias.is_empty() { None } else { Some(alias.clone()) },
                    quality: entry.quality,
                    last_seen: now,
                });
                if is_new {
                    info!(call = %call, alias = %alias, quality = entry.quality, "New route discovered");
                } else {
                    trace!(call = %call, quality = entry.quality, "Route updated");
                }
            }
        }
    }

    /// Check if we have a route to a specific callsign
    pub fn has_route(&self, callsign: &str) -> bool {
        if let Some(route) = self.routes.get(callsign) {
            // Check if route is still valid (not expired)
            route.last_seen.elapsed() < ROUTE_TIMEOUT
        } else {
            false
        }
    }

    /// Add a learned route from receiving traffic from a node
    /// (Used when LinBPQ doesn't forward NODES broadcasts)
    pub fn add_learned_route(&mut self, callsign: &str) {
        info!(call = %callsign, "Learned route from incoming traffic");
        self.routes.insert(callsign.to_string(), Route {
            dest_call: callsign.to_string(),
            alias: None,
            quality: 128, // Medium quality since we don't know the actual quality
            last_seen: Instant::now(),
        });
    }

    /// Get all known node callsigns
    pub fn known_nodes(&self) -> Vec<String> {
        self.routes.keys().cloned().collect()
    }

    /// Clean up expired routes
    pub fn cleanup(&mut self) {
        let now = Instant::now();
        self.routes.retain(|call, route| {
            let expired = route.last_seen.elapsed() >= ROUTE_TIMEOUT;
            if expired {
                debug!(call = %call, "Route expired");
            }
            !expired
        });
    }
}

/// Maximum concurrent sessions
const MAX_SESSIONS: usize = 64;

/// Session manager for L4 connections
pub struct SessionManager {
    /// Our node callsign (L3 address)
    our_node: Callsign,
    /// Our user/application callsign (L4 address, e.g., WA2M-9 for chat)
    our_user: Callsign,
    /// Active sessions by ID
    sessions: HashMap<SessionId, L4Session>,
    /// Next circuit index to allocate
    next_index: u8,
    /// Circuit ID counter (combined with index for uniqueness)
    next_id: u8,
    /// Session inactivity timeout (like LinBPQ's L4LIMIT)
    session_timeout: Duration,
    /// T1 retransmission timeout
    t1_timeout: Duration,
    /// Per-session send buffers for batching multiple messages into single frames
    send_buffers: HashMap<SessionId, Vec<u8>>,
}

impl SessionManager {
    /// Create a new session manager
    ///
    /// # Arguments
    /// * `session_timeout` - Inactivity timeout in seconds (default 900 = 15 min)
    /// * `t1_timeout` - T1 retransmission timeout in seconds (default 60)
    pub fn new(our_node: Callsign, our_user: Callsign, session_timeout: u64, t1_timeout: u64) -> Self {
        // Use current time to seed starting circuit index
        // This reduces collisions with stale sessions after restart
        let start_index = {
            use std::time::{SystemTime, UNIX_EPOCH};
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.subsec_nanos())
                .unwrap_or(0);
            // Use lower bits of nanoseconds, but avoid 0
            let idx = (nanos & 0xFF) as u8;
            if idx == 0 { 1 } else { idx }
        };

        debug!(start_index, "Initialized session manager with random circuit index");

        Self {
            our_node,
            our_user,
            sessions: HashMap::new(),
            next_index: start_index,
            next_id: 1,
            session_timeout: Duration::from_secs(session_timeout),
            t1_timeout: Duration::from_secs(t1_timeout),
            send_buffers: HashMap::new(),
        }
    }

    /// Clear all sessions (e.g., after transport reconnect)
    ///
    /// When the underlying transport disconnects, all L4 sessions become invalid
    /// because circuit IDs are assigned by the remote end. This must be called
    /// before creating new sessions after a reconnect.
    pub fn clear_all(&mut self) {
        let count = self.sessions.len();
        if count > 0 {
            info!("Clearing {} stale sessions after transport reconnect", count);
            self.sessions.clear();
            self.send_buffers.clear();
            crate::metrics::SESSIONS_ACTIVE.set(0);
        }
    }

    /// Allocate a new session ID
    fn allocate_id(&mut self) -> Option<SessionId> {
        if self.sessions.len() >= MAX_SESSIONS {
            warn!("Maximum sessions reached");
            return None;
        }

        // Find an unused index/id pair
        for _ in 0..256 {
            let id = SessionId::new(self.next_index, self.next_id);

            // Increment for next time
            self.next_id = self.next_id.wrapping_add(1);
            if self.next_id == 0 {
                self.next_index = self.next_index.wrapping_add(1);
                if self.next_index == 0 {
                    self.next_index = 1;
                }
            }

            // Check if unused
            if !self.sessions.contains_key(&id) {
                return Some(id);
            }
        }

        warn!("Could not allocate session ID");
        None
    }

    /// Create a new outbound session to a remote user
    pub fn create_outbound(
        &mut self,
        remote_user: Callsign,
        remote_node: Callsign,
    ) -> Option<SessionId> {
        let id = self.allocate_id()?;

        let session = L4Session::new_outbound(
            id,
            self.our_user.clone(),
            self.our_node.clone(),
            remote_user.clone(),
            remote_node.clone(),
            self.session_timeout,
            self.t1_timeout,
        );

        debug!(
            id = %id,
            remote_user = %remote_user,
            remote_node = %remote_node,
            "Created outbound session"
        );

        self.sessions.insert(id, session);
        crate::metrics::SESSIONS_CREATED.with_label_values(&["outbound"]).inc();
        crate::metrics::SESSIONS_ACTIVE.inc();
        Some(id)
    }

    /// Create a new inbound session from a CREQ
    pub fn create_inbound(&mut self, creq_frame: &NetromFrame) -> Option<SessionId> {
        let id = self.allocate_id()?;

        let session = L4Session::new_inbound(
            id,
            self.our_user.clone(),
            self.our_node.clone(),
            creq_frame,
            self.session_timeout,
            self.t1_timeout,
        )?;

        debug!(
            id = %id,
            remote_user = %session.remote_user(),
            remote_node = %session.remote_node(),
            "Created inbound session"
        );

        self.sessions.insert(id, session);
        crate::metrics::SESSIONS_CREATED.with_label_values(&["inbound"]).inc();
        crate::metrics::SESSIONS_ACTIVE.inc();
        Some(id)
    }

    /// Get a session by ID
    pub fn get(&self, id: &SessionId) -> Option<&L4Session> {
        self.sessions.get(id)
    }

    /// Get a mutable session by ID
    pub fn get_mut(&mut self, id: &SessionId) -> Option<&mut L4Session> {
        self.sessions.get_mut(id)
    }

    /// Find session by remote's circuit info (for incoming frames)
    pub fn find_by_their_circuit(&self, their_index: u8, their_id: u8) -> Option<&SessionId> {
        for (id, session) in &self.sessions {
            if session.their_index == their_index && session.their_id == their_id {
                return Some(id);
            }
        }
        None
    }

    /// Find session by remote user callsign
    pub fn find_by_remote_user(&self, remote_user: &Callsign) -> Option<&SessionId> {
        for (id, session) in &self.sessions {
            if session.remote_user().to_string() == remote_user.to_string() {
                return Some(id);
            }
        }
        None
    }

    /// Check if we have a connected session to a given callsign
    /// Only returns true for sessions in Connected state (not Connecting or Disconnecting)
    pub fn has_session_to(&self, callsign: &str) -> bool {
        self.find_session_to(callsign).is_some()
    }

    /// Find a connected session to a given callsign, returning its SessionId
    pub fn find_session_to(&self, callsign: &str) -> Option<SessionId> {
        for (id, session) in &self.sessions {
            if session.remote_user().to_string() == callsign {
                if session.state() == SessionState::Connected {
                    return Some(*id);
                }
            }
        }
        None
    }

    /// Find an outbound session to a remote user that is Connecting or Connected
    /// Returns the session ID if found
    fn find_outbound_session_to(&self, remote_user: &str) -> Option<SessionId> {
        for (id, session) in &self.sessions {
            if session.remote_user().to_string() == remote_user && session.is_outbound() {
                match session.state() {
                    SessionState::Connecting | SessionState::Connected => {
                        return Some(*id);
                    }
                    _ => {}
                }
            }
        }
        None
    }

    /// Find an inbound session from a remote user that is Connected
    /// Returns the session ID if found
    fn find_inbound_session_from(&self, remote_user: &str) -> Option<SessionId> {
        for (id, session) in &self.sessions {
            if session.remote_user().to_string() == remote_user && !session.is_outbound() {
                if session.state() == SessionState::Connected {
                    return Some(*id);
                }
            }
        }
        None
    }

    /// Apply tie-breaker logic when both ends try to connect
    /// Returns true if we should accept their inbound (they win)
    /// Uses lexicographic callsign comparison - higher callsign wins
    fn should_accept_inbound(&self, their_user: &str) -> bool {
        let our_call = self.our_user.to_string();
        // Higher callsign wins - if they're higher, we accept their inbound
        their_user > our_call.as_str()
    }

    /// Find session by our circuit (for incoming frames addressed to us)
    pub fn find_by_our_circuit(&self, our_index: u8, our_id: u8) -> Option<&SessionId> {
        let id = SessionId::new(our_index, our_id);
        if self.sessions.contains_key(&id) {
            // Return a reference to the key in the map
            self.sessions.keys().find(|k| **k == id)
        } else {
            None
        }
    }

    /// Handle an incoming frame and return events
    ///
    /// The frame is routed to the appropriate session based on circuit info.
    /// For CREQ frames, a new session may be created.
    pub fn handle_frame(&mut self, frame: &NetromFrame) -> (Option<SessionId>, Vec<SessionEvent>) {
        // For CREQ, look up by our node callsign in L3 dest
        if frame.l4.opcode == L4Opcode::ConnectRequest {
            // Check if addressed to us
            if frame.l3.dest.to_string() != self.our_node.to_string() {
                trace!(
                    dest = %frame.l3.dest,
                    our_node = %self.our_node,
                    "CREQ not addressed to us"
                );
                return (None, vec![]);
            }

            // Parse CREQ to get details
            let creq = match crate::netrom::ConnectRequest::parse(&frame.data) {
                Some(c) => c,
                None => {
                    warn!("Failed to parse CREQ");
                    return (None, vec![]);
                }
            };

            let remote_user = creq.origin_user.to_string();

            debug!(
                l3_src = %frame.l3.source,
                l3_dest = %frame.l3.dest,
                l4_idx = frame.l4.circuit_index,
                l4_id = frame.l4.circuit_id,
                creq_window = creq.window,
                creq_origin_user = %remote_user,
                creq_origin_node = %creq.origin_node,
                creq_timeout = creq.timeout,
                "Received CREQ"
            );

            // Check for existing inbound session from same user (duplicate CREQ)
            // If we already have a connected inbound session, just resend CACK
            if let Some(existing_id) = self.find_inbound_session_from(&remote_user) {
                if let Some(session) = self.sessions.get(&existing_id) {
                    debug!(
                        remote = %remote_user,
                        existing_session = %existing_id,
                        "Duplicate CREQ from existing inbound session, resending CACK"
                    );
                    let cack = session.accept();
                    return (
                        Some(existing_id),
                        vec![SessionEvent::Transmit(vec![cack])],
                    );
                }
            }

            // Check for existing outbound session to this user
            if let Some(existing_id) = self.find_outbound_session_to(&remote_user) {
                let outbound_state = self.sessions.get(&existing_id)
                    .map(|s| s.state());

                if outbound_state == Some(SessionState::Connected) {
                    // Our outbound is already connected and working
                    // Ignore their CREQ - it may be stale from before we connected
                    debug!(
                        remote = %remote_user,
                        existing_session = %existing_id,
                        "CREQ while outbound already connected, ignoring"
                    );
                    return (None, vec![]);
                } else {
                    // Our outbound is in Connecting state (CREQ sent, no CACK yet)
                    // Accept their inbound - their CREQ proves they're ready to
                    // connect now, while our outbound CREQ may have been lost
                    info!(
                        remote = %remote_user,
                        existing_session = %existing_id,
                        outbound_state = ?outbound_state,
                        "CREQ while outbound pending, accepting inbound"
                    );
                    self.sessions.remove(&existing_id);
                }
            }

            // Create inbound session
            if let Some(id) = self.create_inbound(frame) {
                let session = self.sessions.get(&id).unwrap();
                let cack = session.accept();
                // IMPORTANT: Transmit CACK first, then signal Connected
                // Connected event triggers NodeLink INFO send, which can't be
                // processed by peer until they receive our CACK
                return (
                    Some(id),
                    vec![
                        SessionEvent::Transmit(vec![cack]),
                        SessionEvent::Connected,
                    ],
                );
            }

            return (None, vec![]);
        }

        // For other frames, look up by circuit index/id
        // The circuit_index and circuit_id in the frame are OUR circuit info
        let session_id = if let Some(id) =
            self.find_by_our_circuit(frame.l4.circuit_index, frame.l4.circuit_id)
        {
            id.clone()
        } else {
            // No session for this circuit - this can happen after restart when
            // remote still has stale sessions.
            // For data frames (INFO/IACK), send L4RESET (Paula's extension) to tell
            // remote to close the session. The RESET includes the circuit info from
            // the incoming frame, which lets LinBPQ find and close the correct session.
            // For DREQ/DACK frames, just ignore - no response needed.
            if matches!(frame.l4.opcode, L4Opcode::Information | L4Opcode::InformationAck) {
                warn!(
                    index = frame.l4.circuit_index,
                    id = frame.l4.circuit_id,
                    opcode = ?frame.l4.opcode,
                    remote = %frame.l3.source,
                    "No session for data frame, sending L4RESET"
                );
                // Send L4RESET with the circuit info from the incoming frame
                // This tells LinBPQ to search for a session with these "far" circuit values
                let reset = NetromFrame::reset(
                    &self.our_node,
                    &frame.l3.source,
                    frame.l4.circuit_index,  // What they think our index is
                    frame.l4.circuit_id,     // What they think our id is
                );
                return (None, vec![SessionEvent::Transmit(vec![reset])]);
            } else {
                trace!(
                    index = frame.l4.circuit_index,
                    id = frame.l4.circuit_id,
                    opcode = ?frame.l4.opcode,
                    remote = %frame.l3.source,
                    "No session for control frame, ignoring"
                );
            }
            return (None, vec![]);
        };

        // Handle the frame in the session
        if let Some(session) = self.sessions.get_mut(&session_id) {
            let events = session.handle_frame(frame);
            return (Some(session_id), events);
        }

        (None, vec![])
    }

    /// Start connection for a session
    pub fn connect(&mut self, id: &SessionId) -> Vec<NetromFrame> {
        if let Some(session) = self.sessions.get_mut(id) {
            session.connect()
        } else {
            vec![]
        }
    }

    /// Send data on a session (immediate - creates frames now)
    pub fn send(&mut self, id: &SessionId, data: &[u8]) -> Vec<NetromFrame> {
        if let Some(session) = self.sessions.get_mut(id) {
            session.send(data)
        } else {
            vec![]
        }
    }

    /// Queue data for batched sending on a session
    ///
    /// Data is buffered until `flush()` or `flush_all()` is called.
    /// This allows multiple messages to be combined into fewer L4 frames.
    pub fn queue(&mut self, id: &SessionId, data: &[u8]) {
        if !self.sessions.contains_key(id) {
            return;
        }
        self.send_buffers
            .entry(*id)
            .or_insert_with(Vec::new)
            .extend_from_slice(data);
    }

    /// Flush queued data for a specific session
    ///
    /// Combines all buffered data into L4 frames and returns them.
    pub fn flush(&mut self, id: &SessionId) -> Vec<NetromFrame> {
        if let Some(buffer) = self.send_buffers.remove(id) {
            if !buffer.is_empty() {
                return self.send(id, &buffer);
            }
        }
        vec![]
    }

    /// Flush queued data for all sessions
    ///
    /// Returns frames grouped by session ID for transmission.
    pub fn flush_all(&mut self) -> Vec<(SessionId, Vec<NetromFrame>)> {
        let session_ids: Vec<SessionId> = self.send_buffers.keys().copied().collect();
        let mut results = Vec::new();

        for id in session_ids {
            let frames = self.flush(&id);
            if !frames.is_empty() {
                results.push((id, frames));
            }
        }

        results
    }

    /// Check if there's any queued data waiting to be flushed
    pub fn has_queued_data(&self) -> bool {
        self.send_buffers.values().any(|buf| !buf.is_empty())
    }

    /// Disconnect a session
    pub fn disconnect(&mut self, id: &SessionId) -> Vec<NetromFrame> {
        if let Some(session) = self.sessions.get_mut(id) {
            session.disconnect()
        } else {
            vec![]
        }
    }

    /// Remove a disconnected session
    pub fn remove(&mut self, id: &SessionId) -> Option<L4Session> {
        self.send_buffers.remove(id);  // Clean up any queued data
        let session = self.sessions.remove(id);
        if session.is_some() {
            crate::metrics::SESSIONS_ACTIVE.dec();
        }
        session
    }

    /// Process timers for all sessions
    pub fn tick(&mut self) -> Vec<(SessionId, Vec<SessionEvent>)> {
        let mut results = Vec::new();

        for (id, session) in &mut self.sessions {
            let events = session.tick();
            if !events.is_empty() {
                results.push((id.clone(), events));
            }
        }

        results
    }

    /// Get all connected session IDs
    pub fn connected_sessions(&self) -> Vec<SessionId> {
        self.sessions
            .iter()
            .filter(|(_, s)| s.state() == SessionState::Connected)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Get count of active sessions
    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    /// Get our node callsign
    pub fn our_node(&self) -> &Callsign {
        &self.our_node
    }

    /// Get our user callsign
    pub fn our_user(&self) -> &Callsign {
        &self.our_user
    }

    /// Iterate over all sessions
    pub fn sessions(&self) -> impl Iterator<Item = (&SessionId, &L4Session)> {
        self.sessions.iter()
    }

    /// Clean up disconnected sessions
    pub fn cleanup(&mut self) -> Vec<SessionId> {
        let disconnected: Vec<_> = self
            .sessions
            .iter()
            .filter(|(_, s)| s.state() == SessionState::Disconnected)
            .map(|(id, _)| id.clone())
            .collect();

        for id in &disconnected {
            debug!(id = %id, "Removing disconnected session");
            self.sessions.remove(id);
        }

        disconnected
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_manager() -> SessionManager {
        SessionManager::new(
            Callsign::from_str("TEST1-1"),
            Callsign::from_str("TEST1-9"),
            900, // 15 min inactivity timeout
            60,  // 60s T1 retransmission timeout
        )
    }

    #[test]
    fn test_create_outbound() {
        let mut mgr = make_manager();

        let id = mgr.create_outbound(
            Callsign::from_str("TEST2-9"),
            Callsign::from_str("TEST2-1"),
        );

        assert!(id.is_some());
        let id = id.unwrap();

        let session = mgr.get(&id);
        assert!(session.is_some());
        assert_eq!(session.unwrap().state(), SessionState::Disconnected);
    }

    #[test]
    fn test_create_inbound() {
        let mut mgr = make_manager();

        let creq = NetromFrame::connect_request(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            &Callsign::from_str("TEST2-9"),
            2,
            99,
            4,
            300,
        );

        let id = mgr.create_inbound(&creq);
        assert!(id.is_some());

        let session = mgr.get(&id.unwrap());
        assert!(session.is_some());
        assert_eq!(session.unwrap().state(), SessionState::Connected);
    }

    #[test]
    fn test_handle_creq() {
        let mut mgr = make_manager();

        let creq = NetromFrame::connect_request(
            &Callsign::from_str("TEST2-1"),
            &Callsign::from_str("TEST1-1"),
            &Callsign::from_str("TEST2-9"),
            2,
            99,
            4,
            300,
        );

        let (session_id, events) = mgr.handle_frame(&creq);

        assert!(session_id.is_some());
        assert!(events.iter().any(|e| matches!(e, SessionEvent::Connected)));
        assert!(events
            .iter()
            .any(|e| matches!(e, SessionEvent::Transmit(frames) if !frames.is_empty())));
    }

    #[test]
    fn test_find_by_circuit() {
        let mut mgr = make_manager();

        let id = mgr
            .create_outbound(
                Callsign::from_str("TEST2-9"),
                Callsign::from_str("TEST2-1"),
            )
            .unwrap();

        // Should find by our circuit
        let found = mgr.find_by_our_circuit(id.our_index, id.our_id);
        assert!(found.is_some());
        assert_eq!(*found.unwrap(), id);
    }

    #[test]
    fn test_session_limit() {
        let mut mgr = make_manager();

        // Create MAX_SESSIONS
        for i in 0..MAX_SESSIONS {
            let id = mgr.create_outbound(
                Callsign::from_str(&format!("TEST{}-9", i)),
                Callsign::from_str(&format!("TEST{}-1", i)),
            );
            assert!(id.is_some(), "Failed to create session {}", i);
        }

        // Next should fail
        let id = mgr.create_outbound(
            Callsign::from_str("EXTRA-9"),
            Callsign::from_str("EXTRA-1"),
        );
        assert!(id.is_none());
    }
}
