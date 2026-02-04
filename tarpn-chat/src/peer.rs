use std::time::{Duration, Instant};
use tracing::info;

use crate::session::SessionId;

/// Minimum backoff for peer connection retry
pub const PEER_MIN_BACKOFF: Duration = Duration::from_secs(5);
/// Maximum backoff for peer connection retry (10 minutes)
pub const PEER_MAX_BACKOFF: Duration = Duration::from_secs(600);
/// Timeout waiting for CACK before considering connection attempt failed
pub const PEER_CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

/// Peer connection phases
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerPhase {
    /// Not connected, can retry after next_retry time
    Idle,
    /// CREQ sent, waiting for CACK (L4 connecting)
    Connecting,
    /// L4 connected, waiting for chat handshake to complete
    Handshaking,
    /// Chat handshake complete, fully connected
    Connected,
}

/// Tracks connection state for a single peer
pub struct PeerConnectionState {
    /// Peer's callsign
    pub call: String,
    /// When to next attempt connection
    pub next_retry: Instant,
    /// Current backoff duration
    pub backoff: Duration,
    /// Current connection phase
    pub phase: PeerPhase,
    /// When we sent the last CREQ (to detect CACK timeout)
    pub last_connect_attempt: Option<Instant>,
    /// Session ID for current connection attempt (to clean up on timeout)
    pub session_id: Option<SessionId>,
}

impl PeerConnectionState {
    pub fn new(call: String) -> Self {
        Self {
            call,
            next_retry: Instant::now(), // Try immediately
            backoff: PEER_MIN_BACKOFF,
            phase: PeerPhase::Idle,
            last_connect_attempt: None,
            session_id: None,
        }
    }

    /// Mark that we've started a connection attempt (CREQ sent)
    pub fn start_connect(&mut self, session_id: SessionId) {
        self.phase = PeerPhase::Connecting;
        self.last_connect_attempt = Some(Instant::now());
        self.session_id = Some(session_id);
    }

    /// Mark L4 as connected, now waiting for chat handshake
    pub fn l4_connected(&mut self) {
        self.phase = PeerPhase::Handshaking;
        // Keep last_connect_attempt for overall timeout tracking
    }

    /// Mark chat handshake as complete - reset backoff
    pub fn handshake_complete(&mut self) {
        self.phase = PeerPhase::Connected;
        self.last_connect_attempt = None;
        self.session_id = None; // Clear - session is now managed normally
        self.backoff = PEER_MIN_BACKOFF;
        info!(
            peer = %self.call,
            "Peer connection fully established, backoff reset"
        );
    }

    /// Mark connection attempt as failed - increase backoff
    /// Returns the session_id if one was being tracked (for cleanup)
    pub fn failed(&mut self, reason: &str) -> Option<SessionId> {
        self.phase = PeerPhase::Idle;
        self.last_connect_attempt = None;
        let session_id = self.session_id.take(); // Take and clear
        // Exponential backoff with max
        self.backoff = (self.backoff * 2).min(PEER_MAX_BACKOFF);
        self.next_retry = Instant::now() + self.backoff;
        info!(
            peer = %self.call,
            reason = %reason,
            backoff_secs = self.backoff.as_secs(),
            "Peer connection failed, backing off"
        );
        session_id
    }

    /// Mark as disconnected (after successful connection) - use backoff
    pub fn disconnected(&mut self) {
        self.phase = PeerPhase::Idle;
        self.last_connect_attempt = None;
        self.session_id = None;
        // Use current backoff (don't increase for normal disconnects)
        self.next_retry = Instant::now() + self.backoff;
        info!(
            peer = %self.call,
            backoff_secs = self.backoff.as_secs(),
            "Peer disconnected, will retry"
        );
    }

    /// Check if CREQ has timed out (no CACK received)
    pub fn has_timed_out(&self) -> bool {
        if let Some(attempt) = self.last_connect_attempt {
            self.phase == PeerPhase::Connecting && attempt.elapsed() > PEER_CONNECT_TIMEOUT
        } else {
            false
        }
    }

    /// Check if ready to retry
    pub fn ready_to_connect(&self) -> bool {
        self.phase == PeerPhase::Idle && Instant::now() >= self.next_retry
    }
}
