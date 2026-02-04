//! Main chat server implementation
//!
//! Manages:
//! - Connection to LinBPQ via NetROM over TCP
//! - Message processing and state management
//! - Auto-reconnection
//! - Message forwarding between peer connections

use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tracing::{debug, error, info, trace, warn};

use crate::client_api::{
    broadcast_message_to_clients, new_client_senders, new_local_clients, run_client_api_server,
    send_to_client, ClientApiEvent, ClientCommand, ClientEvent, ClientSenders, LocalClients,
    NodeInfo, UserInfo,
};
use crate::config::Config;
use crate::netrom::{Callsign, Inp3Rif, RttMessage, create_rtt_request, is_rtt_frame, is_rtt_reply};
use crate::peer::{PeerConnectionState, PeerPhase};
use crate::protocol::{ChatConnection, ChatEvent, Message};
use crate::routing::SessionManager;
use crate::session::{SessionEvent, SessionId};
use crate::state::{new_shared_state, Circuit, CircuitState, SharedState};
use crate::transport::{NetromTransport, ReceivedFrame};
use crate::utils::strip_ssid;

/// Main chat server
pub struct ChatServer {
    config: Config,
    state: SharedState,
}

impl ChatServer {
    /// Create a new chat server with the given configuration
    pub fn new(config: Config) -> Self {
        let state = new_shared_state(config.node.call.clone(), config.node.alias.clone());
        Self { config, state }
    }

    /// Run the chat server
    pub async fn run(&mut self) -> anyhow::Result<()> {
        info!(
            "Starting chat node {} ({})",
            self.config.node.call, self.config.node.alias
        );

        // Always run in NetROM mode
        self.run_netrom_mode().await
    }

    /// Run in NetROM mode - connect to or accept connections from LinBPQ
    async fn run_netrom_mode(&mut self) -> anyhow::Result<()> {
        let netrom_config = self.config.netrom.clone()
            .expect("netrom config required for netrom mode");

        let our_call = Callsign::from_str(&self.config.node.call);

        // Determine connection mode
        let is_listen_mode = netrom_config.listen.is_some();
        let addr = if let Some(ref listen_addr) = netrom_config.listen {
            info!("NetROM mode: listening for LinBPQ connections on {}", listen_addr);
            listen_addr.clone()
        } else if let Some(ref linbpq_addr) = netrom_config.linbpq {
            info!("NetROM mode: connecting to LinBPQ at {}", linbpq_addr);
            linbpq_addr.clone()
        } else {
            return Err(anyhow::anyhow!("NetROM config must specify either 'linbpq' or 'listen'"));
        };

        // Session manager for L4 connections
        let mut session_mgr = SessionManager::new(
            our_call.clone(),
            our_call.clone(),
            netrom_config.timeout,  // session inactivity timeout (default 15 min)
            netrom_config.t1,       // T1 retransmission timeout (default 60s)
        );

        // Client API for local WebSocket clients
        let client_senders: ClientSenders = new_client_senders();
        let local_clients: LocalClients = new_local_clients();
        let (client_tx, mut client_rx) = mpsc::channel::<ClientApiEvent>(256);

        // Start client API server if configured
        if let Some(ref client_config) = self.config.client {
            let listen_addr: SocketAddr = format!("{}:{}", client_config.bind, client_config.port)
                .parse()
                .expect("Invalid client API bind address");

            let client_tx_clone = client_tx.clone();
            let client_senders_clone = client_senders.clone();
            let local_clients_clone = local_clients.clone();

            tokio::spawn(async move {
                if let Err(e) = run_client_api_server(
                    listen_addr,
                    client_tx_clone,
                    client_senders_clone,
                    local_clients_clone,
                )
                .await
                {
                    error!("Client API server error: {}", e);
                }
            });

            info!("Client API server listening on {}", listen_addr);
        }

        // Listen mode: accept connections from LinBPQ
        if is_listen_mode {
            return self.run_netrom_listen_mode(
                &addr,
                &our_call,
                &mut session_mgr,
                &client_senders,
                &local_clients,
                &mut client_rx,
            ).await;
        }

        // Connect mode: connect out to LinBPQ
        let linbpq_addr = addr;

        // Main reconnection loop
        loop {
            match self.run_netrom_connection(
                &linbpq_addr,
                &our_call,
                &mut session_mgr,
                &client_senders,
                &local_clients,
                &mut client_rx,
            ).await {
                Ok(()) => {
                    info!("NetROM connection ended normally");
                }
                Err(e) => {
                    error!("NetROM connection error: {}", e);
                }
            }

            // Always reconnect for NetROM mode
            let delay = Duration::from_secs(30);
            info!("Reconnecting to LinBPQ in {} seconds...", delay.as_secs());
            tokio::time::sleep(delay).await;
        }
    }

    /// Run in NetROM listen mode - wait for LinBPQ to connect to us
    async fn run_netrom_listen_mode(
        &mut self,
        listen_addr: &str,
        our_call: &Callsign,
        session_mgr: &mut SessionManager,
        client_senders: &ClientSenders,
        local_clients: &LocalClients,
        client_rx: &mut mpsc::Receiver<ClientApiEvent>,
    ) -> anyhow::Result<()> {
        use crate::transport::NetromListener;

        let listener = NetromListener::bind(listen_addr, our_call.clone()).await
            .map_err(|e| anyhow::anyhow!("Failed to bind: {}", e))?;

        info!("Listening for LinBPQ connections on {}", listen_addr);

        loop {
            // Wait for a connection from LinBPQ
            info!("Waiting for LinBPQ to connect...");
            let mut transport = listener.accept().await
                .map_err(|e| anyhow::anyhow!("Accept failed: {}", e))?;

            info!("LinBPQ connected from {}", transport.peer_addr());

            // Run the connection handling loop
            if let Err(e) = self.run_netrom_transport_loop(
                &mut transport,
                our_call,
                session_mgr,
                client_senders,
                local_clients,
                client_rx,
            ).await {
                error!("NetROM connection error: {}", e);
            }

            info!("LinBPQ disconnected, waiting for reconnection...");
        }
    }

    /// Run a single NetROM connection until disconnected (connect mode)
    async fn run_netrom_connection(
        &mut self,
        linbpq_addr: &str,
        our_call: &Callsign,
        session_mgr: &mut SessionManager,
        client_senders: &ClientSenders,
        local_clients: &LocalClients,
        client_rx: &mut mpsc::Receiver<ClientApiEvent>,
    ) -> anyhow::Result<()> {
        // Connect to LinBPQ
        let mut transport = NetromTransport::connect(linbpq_addr, our_call.clone()).await
            .map_err(|e| anyhow::anyhow!("Failed to connect: {}", e))?;

        info!("Connected to LinBPQ NETROMPORT at {}", transport.peer_addr());

        // Send INP3 RIF to announce ourselves as a reachable destination
        let mut inp3_rif = Inp3Rif::new();
        inp3_rif.add_self(&self.config.node.call, &self.config.node.alias);

        let rif_data = inp3_rif.encode();
        transport.send_raw(&rif_data).await
            .map_err(|e| anyhow::anyhow!("Failed to send INP3 RIF: {}", e))?;

        info!(
            "Sent INP3 RIF announcing {} ({})",
            self.config.node.call, self.config.node.alias
        );

        self.run_netrom_transport_loop(
            &mut transport,
            our_call,
            session_mgr,
            client_senders,
            local_clients,
            client_rx,
        ).await
    }

    /// Common transport loop for both connect and listen modes
    async fn run_netrom_transport_loop(
        &mut self,
        transport: &mut NetromTransport,
        our_call: &Callsign,
        session_mgr: &mut SessionManager,
        client_senders: &ClientSenders,
        local_clients: &LocalClients,
        client_rx: &mut mpsc::Receiver<ClientApiEvent>,
    ) -> anyhow::Result<()> {
        // Clear any stale sessions from previous connection
        // L4 circuit IDs are invalid after transport reconnect
        session_mgr.clear_all();

        // Timer for session maintenance
        let mut tick_interval = tokio::time::interval(Duration::from_secs(5));

        // INP3 RTT state for keepalive
        let rtt_start = Instant::now();
        let mut rtt_id: u32 = 0;
        let mut rtt_srtt: u32 = 0;
        let mut rtt_last: u32 = 0;
        let mut rtt_last_send = Instant::now();
        let rtt_interval = Duration::from_secs(30);

        // Chat keepalive timer - matches LinBPQ's 10-minute interval
        let mut keepalive_last_send = Instant::now();
        let keepalive_interval = Duration::from_secs(600); // 10 minutes

        // Peer connection tracking with retry/backoff
        let mut peer_states: Vec<PeerConnectionState> = self.config.peers.iter()
            .map(|p| PeerConnectionState::new(p.call.clone()))
            .collect();

        if !peer_states.is_empty() {
            let peer_calls: Vec<&str> = peer_states.iter().map(|p| p.call.as_str()).collect();
            info!(
                "Will attempt connections to peers: {:?}",
                peer_calls
            );
        }

        let our_call_str = self.config.node.call.clone();
        let our_alias = self.config.node.alias.clone();

        // Chat protocol connections (application layer above L4)
        let mut chat_connections: HashMap<SessionId, ChatConnection> = HashMap::new();

        // Map session IDs to their circuit IDs for proper transitive node cleanup
        let mut session_circuits: HashMap<SessionId, crate::state::CircuitId> = HashMap::new();

        loop {
            tokio::select! {
                // Receive NetROM frames
                result = transport.recv_frame() => {
                    match result {
                        Ok(received) => {
                            self.handle_netrom_frame(
                                received,
                                transport,
                                session_mgr,
                                &mut chat_connections,
                                &mut session_circuits,
                                &our_call_str,
                                &our_alias,
                                &mut peer_states,
                                client_senders,
                            ).await?;
                            // Flush any queued messages (enables batching multiple messages)
                            Self::flush_queued_data(session_mgr, transport).await?;
                        }
                        Err(e) => {
                            crate::metrics::TRANSPORT_TCP_DISCONNECTS.inc();
                            return Err(anyhow::anyhow!("Transport error: {}", e));
                        }
                    }
                }

                // Handle client API events
                Some(client_event) = client_rx.recv() => {
                    self.handle_netrom_client_event(
                        client_event,
                        &our_call_str,
                        transport,
                        session_mgr,
                        client_senders,
                        local_clients,
                    ).await?;
                    // Flush any queued messages
                    Self::flush_queued_data(session_mgr, transport).await?;
                }

                // Session timer tick
                _ = tick_interval.tick() => {
                    let timer_events = session_mgr.tick();
                    for (session_id, events) in timer_events {
                        for event in events {
                            self.handle_session_event(
                                &session_id,
                                event,
                                transport,
                                session_mgr,
                                &mut chat_connections,
                                &mut session_circuits,
                                &our_call_str,
                                &our_alias,
                                &mut peer_states,
                                client_senders,
                            ).await?;
                        }
                    }

                    // Clean up disconnected sessions
                    session_mgr.cleanup();

                    // Send periodic INP3 RTT message for keepalive
                    if rtt_last_send.elapsed() >= rtt_interval {
                        let tx_time = (rtt_start.elapsed().as_millis() / 10) as u32;
                        let rtt_frame = create_rtt_request(
                            our_call,
                            tx_time,
                            rtt_srtt,
                            rtt_last,
                            rtt_id,
                            &self.config.node.alias,
                        );
                        rtt_id = rtt_id.wrapping_add(1);
                        rtt_last_send = Instant::now();

                        if let Err(e) = transport.send_frame(&rtt_frame).await {
                            warn!("Failed to send RTT: {}", e);
                        } else {
                            debug!("Sent INP3 RTT (id={}, tx_time={})", rtt_id - 1, tx_time);
                        }
                    }

                    // Send periodic chat keepalives to all connected peers (every 10 min like LinBPQ)
                    if keepalive_last_send.elapsed() >= keepalive_interval {
                        keepalive_last_send = Instant::now();
                        let connected = session_mgr.connected_sessions();
                        for sid in &connected {
                            if let Some(chat_conn) = chat_connections.get(sid) {
                                if let Some(remote) = chat_conn.remote_node() {
                                    let ka = Message::Keepalive(crate::protocol::KeepaliveMessage {
                                        src_node: our_call_str.clone(),
                                        dest_node: remote.to_string(),
                                        version: Some(crate::protocol::VERSION.to_string()),
                                    });
                                    let encoded = ka.encode();
                                    session_mgr.queue(sid, &encoded);
                                    debug!(session = %sid, remote = %remote, "Sent periodic keepalive");
                                }
                            }
                        }
                        // Flush keepalives
                        Self::flush_queued_data(session_mgr, transport).await?;
                    }

                    // Manage peer connections with retry/backoff
                    for peer_state in &mut peer_states {
                        // Check if connected session exists
                        let has_session = session_mgr.has_session_to(&peer_state.call);

                        if has_session && peer_state.phase == PeerPhase::Connecting {
                            // L4 connected, now waiting for chat handshake
                            peer_state.l4_connected();
                            info!(peer = %peer_state.call, "L4 connected, waiting for chat handshake");
                        } else if peer_state.has_timed_out() {
                            // CREQ timed out, no CACK received - clean up session
                            if let Some(stale_session_id) = peer_state.failed("CREQ timeout") {
                                // Remove the stale session so tie-breaker doesn't see it
                                session_mgr.remove(&stale_session_id);
                                debug!(
                                    peer = %peer_state.call,
                                    session = %stale_session_id,
                                    "Removed stale session after CREQ timeout"
                                );
                            }
                        } else if !has_session && peer_state.ready_to_connect() {
                            // Time to try connecting
                            let call = Callsign::from_str(&peer_state.call);
                            if let Some(session_id) = session_mgr.create_outbound(
                                call.clone(),
                                call.clone(),
                            ) {
                                let frames = session_mgr.connect(&session_id);
                                for frame in frames {
                                    if let Err(e) = transport.send_frame(&frame).await {
                                        warn!("Failed to send CREQ to {}: {}", peer_state.call, e);
                                    }
                                }
                                peer_state.start_connect(session_id);
                                info!(
                                    peer = %peer_state.call,
                                    backoff_secs = peer_state.backoff.as_secs(),
                                    "Attempting peer connection"
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    /// Handle an incoming NetROM frame (either L4 frame or NODES broadcast)
    async fn handle_netrom_frame(
        &mut self,
        received: ReceivedFrame,
        transport: &mut NetromTransport,
        session_mgr: &mut SessionManager,
        chat_connections: &mut HashMap<SessionId, ChatConnection>,
        session_circuits: &mut HashMap<SessionId, crate::state::CircuitId>,
        our_call: &str,
        our_alias: &str,
        peer_states: &mut [PeerConnectionState],
        client_senders: &ClientSenders,
    ) -> anyhow::Result<()> {
        match received {
            ReceivedFrame::Frame { from_call: _, frame } => {
                // Check if this is an INP3 RTT frame
                if is_rtt_frame(&frame) {
                    let our_call = Callsign::from_str(&self.config.node.call);

                    if is_rtt_reply(&frame, &our_call) {
                        // This is a reply to our RTT request - calculate RTT
                        if let Some(rtt_msg) = RttMessage::parse(&frame.data) {
                            debug!(
                                "Received RTT reply: tx_time={}, id={}, from={}",
                                rtt_msg.tx_time, rtt_msg.rtt_id, rtt_msg.alias
                            );
                        }
                    } else {
                        // This is an RTT request from neighbor - echo it back
                        debug!(
                            "Received RTT request from {}, echoing back",
                            frame.l3.source
                        );
                        transport.send_frame(&frame).await
                            .map_err(|e| anyhow::anyhow!("Failed to echo RTT: {}", e))?;
                    }
                    return Ok(());
                }

                let (session_id, events) = session_mgr.handle_frame(&frame);

                // Process events - some events (like Transmit for L4RESET) don't have
                // an associated session, so we handle those first
                for event in events {
                    if let SessionEvent::Transmit(frames) = event {
                        // Transmit events can happen without a session (e.g., L4RESET)
                        for frame in frames {
                            transport.queue_frame(&frame)
                                .map_err(|e| anyhow::anyhow!("Queue error: {}", e))?;
                        }
                        transport.flush().await
                            .map_err(|e| anyhow::anyhow!("Flush error: {}", e))?;
                    } else if let Some(ref sid) = session_id {
                        // Other events require a valid session
                        self.handle_session_event(
                            sid,
                            event,
                            transport,
                            session_mgr,
                            chat_connections,
                            session_circuits,
                            our_call,
                            our_alias,
                            peer_states,
                            client_senders,
                        ).await?;
                    }
                }
            }

            ReceivedFrame::Nodes { from_call, broadcast } => {
                // Log NODES broadcast (we use retry-based connections, not route discovery)
                debug!(
                    from = %from_call,
                    routes = broadcast.routes.len(),
                    "Received NODES broadcast"
                );
            }
        }

        Ok(())
    }

    /// Handle a session event
    async fn handle_session_event(
        &mut self,
        session_id: &SessionId,
        event: SessionEvent,
        transport: &mut NetromTransport,
        session_mgr: &mut SessionManager,
        chat_connections: &mut HashMap<SessionId, ChatConnection>,
        session_circuits: &mut HashMap<SessionId, crate::state::CircuitId>,
        our_call: &str,
        our_alias: &str,
        peer_states: &mut [PeerConnectionState],
        client_senders: &ClientSenders,
    ) -> anyhow::Result<()> {
        match event {
            SessionEvent::Connected => {
                if let Some(session) = session_mgr.get(session_id) {
                    let peer_call = session.remote_user().to_string();
                    let is_outbound = session.is_outbound();
                    crate::metrics::PEERS_CONNECTED
                        .with_label_values(&[&peer_call])
                        .set(1);
                    info!(
                        "Session {} connected to {} ({})",
                        session_id,
                        peer_call,
                        if is_outbound { "outbound" } else { "inbound" }
                    );

                    // Add peer to state and track circuit for this session
                    let session_circuit_id = {
                        let mut state = self.state.write().await;
                        let circuit_id = state.next_circuit_id();
                        let mut circuit = Circuit::new(circuit_id, peer_call.clone(), false);
                        circuit.state = CircuitState::Connected;
                        state.add_circuit(circuit);
                        state.add_node_route(circuit_id, &peer_call, &strip_ssid(&peer_call), None);
                        circuit_id
                    };
                    session_circuits.insert(*session_id, session_circuit_id);

                    // Create ChatConnection for this session
                    let mut chat_conn = ChatConnection::new(our_call, our_alias, is_outbound, Some(&peer_call));

                    // Process initial events (sends SID for inbound)
                    let events = chat_conn.on_connected();
                    self.process_chat_events(
                        session_id,
                        events,
                        transport,
                        session_mgr,
                        session_circuits,
                        &peer_call,
                        peer_states,
                        client_senders,
                    ).await?;

                    // Store the connection
                    chat_connections.insert(*session_id, chat_conn);
                }
            }

            SessionEvent::Disconnected { reason } => {
                // Get peer info before removing chat connection
                let peer_info = chat_connections.get(session_id)
                    .map(|c| (c.is_linked(), c.remote_node().map(|s| s.to_string())));

                // Also try to get peer call from session manager
                let peer_call = session_mgr.get(session_id)
                    .map(|s| s.remote_user().to_string());

                // Track metrics
                let reason_label = if reason.contains("Timeout") {
                    "timeout"
                } else if reason.contains("isconnect") {
                    "disconnect"
                } else {
                    "error"
                };
                crate::metrics::SESSIONS_DESTROYED
                    .with_label_values(&[reason_label])
                    .inc();
                if let Some(ref call) = peer_call {
                    crate::metrics::PEERS_CONNECTED
                        .with_label_values(&[call])
                        .set(0);
                }

                info!("Session {} disconnected: {}", session_id, reason);

                // Get remote node name from chat connection before removing it
                let remote_node = chat_connections.get(session_id)
                    .and_then(|c| c.remote_node().map(|s| s.to_string()));
                let was_linked = chat_connections.get(session_id)
                    .map(|c| c.is_linked())
                    .unwrap_or(false);

                // Remove chat connection
                if let Some(mut chat_conn) = chat_connections.remove(session_id) {
                    chat_conn.close();
                }

                // Remove session from session manager so tie-breaker doesn't see stale sessions
                session_mgr.remove(session_id);

                // Generate Leave and NodeUnlink messages for the disconnected peer
                // and all nodes that were only reachable through it (transitive nodes)
                if was_linked {
                    // Look up and remove the circuit for this session — this cleans up
                    // transitive node reachability tracked by add_node_route()
                    let circuit_id = session_circuits.remove(session_id);
                    let (lost_nodes, removed_users) = {
                        let mut state = self.state.write().await;

                        // Get the list of nodes that will become unreachable when
                        // we remove this circuit
                        let mut lost_nodes = Vec::new();
                        if let Some(cid) = circuit_id {
                            if let Some(circuit) = state.get_circuit(cid) {
                                for node_call in &circuit.reachable_nodes {
                                    if let Some(node) = state.nodes.get(node_call) {
                                        // Node is lost if this is its only circuit
                                        if node.circuits.len() == 1 && node.is_reachable_via(cid) {
                                            lost_nodes.push(node_call.clone());
                                        }
                                    }
                                }
                            }
                            state.remove_circuit(cid);
                        } else if let Some(ref lost_node) = remote_node {
                            // Fallback: no circuit tracked (shouldn't happen for linked sessions)
                            // At minimum, mark the direct peer as lost
                            lost_nodes.push(lost_node.clone());
                        }

                        // Remove users on ALL lost nodes
                        let mut all_removed = Vec::new();
                        for node_call in &lost_nodes {
                            let removed = state.remove_users_on_node(node_call);
                            all_removed.extend(removed);
                        }

                        (lost_nodes, all_removed)
                    };

                    // Generate Leave messages for all removed users
                    for user in &removed_users {
                        let leave_msg = Message::Leave(crate::protocol::LeaveMessage {
                            node: user.node_call.clone(),
                            user: user.call.clone(),
                            name: user.name.clone(),
                            qth: user.qth.clone(),
                        });

                        info!("Generating leave for {}@{} (peer disconnected)", user.call, user.node_call);

                        // Forward to other connected sessions
                        let encoded = leave_msg.encode();
                        let connected = session_mgr.connected_sessions();
                        for other_id in connected {
                            if other_id != *session_id {
                                session_mgr.queue(&other_id, &encoded);
                            }
                        }

                        // Broadcast to local WebSocket clients
                        broadcast_message_to_clients(client_senders, &leave_msg).await;
                    }

                    // Generate NodeUnlink for each lost node
                    for lost_node in &lost_nodes {
                        let unlink_msg = Message::NodeUnlink(crate::protocol::NodeUnlinkMessage {
                            node: our_call.to_string(),
                            lost_node: lost_node.clone(),
                        });

                        info!("Generating node unlink for {} (peer disconnected)", lost_node);

                        // Forward to other connected sessions
                        let encoded = unlink_msg.encode();
                        let connected = session_mgr.connected_sessions();
                        for other_id in connected {
                            if other_id != *session_id {
                                session_mgr.queue(&other_id, &encoded);
                            }
                        }

                        // Broadcast to local WebSocket clients
                        broadcast_message_to_clients(client_senders, &unlink_msg).await;
                    }
                }

                // Update peer state if this was an outbound peer connection
                let peer_call_to_check = peer_call
                    .or_else(|| peer_info.as_ref().and_then(|(_, n)| n.clone()));

                if let Some(ref call) = peer_call_to_check {
                    if let Some(peer_state) = peer_states.iter_mut().find(|p| p.call == *call) {
                        match peer_state.phase {
                            PeerPhase::Handshaking => {
                                // Disconnect before handshake complete - this is a failure
                                // Session is already being removed by disconnect handling
                                let _ = peer_state.failed(&format!("disconnected during handshake: {}", reason));
                            }
                            PeerPhase::Connected => {
                                // Normal disconnect - use backoff but don't increase
                                peer_state.disconnected();
                            }
                            _ => {
                                // Idle or Connecting - shouldn't happen but handle gracefully
                                debug!(peer = %call, phase = ?peer_state.phase,
                                    "Session disconnected in unexpected phase");
                            }
                        }
                    }
                }
            }

            SessionEvent::DataReceived(data) => {
                // Log both size and content for debugging handshake issues
                let text = String::from_utf8_lossy(&data);
                trace!(
                    len = data.len(),
                    content = %text.replace('\r', "\\r").replace('\n', "\\n"),
                    "DataReceived"
                );

                // Get peer call from session (for peer state tracking)
                let peer_call = session_mgr.get(session_id)
                    .map(|s| s.remote_user().to_string())
                    .unwrap_or_default();

                // Get or create chat connection
                if let Some(chat_conn) = chat_connections.get_mut(session_id) {
                    // Pass data to chat connection
                    let events = chat_conn.receive_data(&data);

                    // Process resulting events
                    self.process_chat_events(
                        session_id,
                        events,
                        transport,
                        session_mgr,
                        session_circuits,
                        &peer_call,
                        peer_states,
                        client_senders,
                    ).await?;
                } else {
                    warn!("DataReceived for unknown session {}", session_id);
                }
            }

            SessionEvent::Transmit(frames) => {
                for frame in frames {
                    transport.queue_frame(&frame)
                        .map_err(|e| anyhow::anyhow!("Queue error: {}", e))?;
                }
                transport.flush().await
                    .map_err(|e| anyhow::anyhow!("Flush error: {}", e))?;
            }
        }

        Ok(())
    }

    /// Process events from a ChatConnection
    async fn process_chat_events(
        &mut self,
        session_id: &SessionId,
        events: Vec<ChatEvent>,
        transport: &mut NetromTransport,
        session_mgr: &mut SessionManager,
        session_circuits: &HashMap<SessionId, crate::state::CircuitId>,
        peer_call: &str,
        peer_states: &mut [PeerConnectionState],
        client_senders: &ClientSenders,
    ) -> anyhow::Result<()> {
        // Batch all Send events together to minimize frame count
        // Small messages like "*RTL\r" and keepalive can fit in a single frame
        let mut send_buffer: Vec<u8> = Vec::new();
        let mut other_events: Vec<ChatEvent> = Vec::new();

        for event in events {
            match event {
                ChatEvent::Send(data) => {
                    send_buffer.extend(data);
                }
                _ => {
                    other_events.push(event);
                }
            }
        }

        // Send batched data first (before processing other events)
        if !send_buffer.is_empty() {
            let frames = session_mgr.send(session_id, &send_buffer);
            for frame in frames {
                transport.queue_frame(&frame)
                    .map_err(|e| anyhow::anyhow!("Queue error: {}", e))?;
            }
            transport.flush().await
                .map_err(|e| anyhow::anyhow!("Flush error: {}", e))?;
        }

        // Process other events
        for event in other_events {
            match event {
                ChatEvent::Send(_) => unreachable!(), // Already handled above

                ChatEvent::HandshakeComplete => {
                    info!("Session {} handshake complete", session_id);
                    crate::metrics::CHAT_HANDSHAKES_COMPLETED.inc();

                    // Update peer state to Connected (reset backoff)
                    // This handles both outbound (Handshaking phase) and inbound connections
                    // (where we might still be in Idle or Connecting from a failed outbound attempt)
                    if let Some(peer_state) = peer_states.iter_mut().find(|p| p.call == peer_call) {
                        if peer_state.phase != PeerPhase::Connected {
                            peer_state.handshake_complete();
                        }
                    }

                    // Announce known nodes and existing users to the new peer.
                    // The circuit-based (direct TCP) path does this in handle_circuit_event,
                    // but session-based (NetROM/CMDPORT) connections need it here.
                    //
                    // Only announce nodes that are fully connected (handshake complete).
                    // Nodes are added to state at L4 connect (before handshake), so we
                    // must cross-reference with peer_states to avoid announcing peers
                    // that are still handshaking.
                    let our_call = &self.config.node.call;

                    // Build set of fully-connected peer calls
                    let connected_peers: std::collections::HashSet<&str> = peer_states
                        .iter()
                        .filter(|p| p.phase == PeerPhase::Connected)
                        .map(|p| p.call.as_str())
                        .collect();

                    // Build set of ALL configured peer calls (any phase)
                    let all_configured_peers: std::collections::HashSet<&str> = peer_states
                        .iter()
                        .map(|p| p.call.as_str())
                        .collect();

                    let (known_nodes, existing_users) = {
                        let state = self.state.read().await;
                        let nodes: Vec<(String, String, Option<String>)> = state.nodes
                            .iter()
                            .filter(|(call, _)| {
                                // Skip ourselves and the new peer's node
                                if *call == our_call || *call == peer_call {
                                    return false;
                                }
                                // If this is a configured peer, only include if fully connected.
                                // If it's a transitively-learned node (not in peer_states), include it
                                // since it was announced by an already-connected peer.
                                if all_configured_peers.contains(call.as_str()) {
                                    return connected_peers.contains(call.as_str());
                                }
                                true
                            })
                            .map(|(call, node)| (call.clone(), node.alias.clone(), node.version.clone()))
                            .collect();

                        // Collect the set of announced node calls for filtering users
                        let announced_nodes: std::collections::HashSet<&str> = nodes
                            .iter()
                            .map(|(call, _, _)| call.as_str())
                            .collect();

                        // Get users: only from our own node or from announced nodes
                        let users: Vec<crate::state::User> = state.users
                            .values()
                            .filter(|u| {
                                u.node_call != peer_call
                                    && (u.node_call == *our_call || announced_nodes.contains(u.node_call.as_str()))
                            })
                            .cloned()
                            .collect();

                        (nodes, users)
                    };

                    // Send NodeLink for each known node
                    for (node_call, node_alias, node_version) in &known_nodes {
                        let alias = if node_alias.is_empty() {
                            strip_ssid(node_call).to_string()
                        } else {
                            node_alias.clone()
                        };
                        let msg = Message::NodeLink(crate::protocol::NodeLinkMessage {
                            node: our_call.clone(),
                            new_node: node_call.clone(),
                            alias,
                            version: node_version.clone(),
                        });
                        let encoded = msg.encode();
                        session_mgr.queue(session_id, &encoded);
                    }

                    // Send Join + Topic for each existing user
                    for user in &existing_users {
                        let join_msg = Message::Join(crate::protocol::JoinMessage {
                            node: user.node_call.clone(),
                            user: user.call.clone(),
                            name: user.name.clone(),
                            qth: user.qth.clone(),
                        });
                        let encoded = join_msg.encode();
                        session_mgr.queue(session_id, &encoded);

                        let topic_msg = Message::Topic(crate::protocol::TopicMessage {
                            node: user.node_call.clone(),
                            user: user.call.clone(),
                            topic: user.topic.clone(),
                        });
                        let encoded = topic_msg.encode();
                        session_mgr.queue(session_id, &encoded);
                    }

                    if !known_nodes.is_empty() || !existing_users.is_empty() {
                        info!(
                            "Announced {} nodes and {} users to new peer {} (session {})",
                            known_nodes.len(),
                            existing_users.len(),
                            peer_call,
                            session_id,
                        );
                    }
                }

                ChatEvent::Message(msg) => {
                    debug!("Received chat message: {:?}", msg);
                    self.handle_chat_message(session_id, msg, transport, session_mgr, session_circuits, client_senders).await?;
                }

                ChatEvent::Error(err) => {
                    warn!("Chat error on session {}: {}", session_id, err);
                    crate::metrics::CHAT_HANDSHAKES_FAILED.inc();

                    // Update peer state to failed (increase backoff)
                    if let Some(peer_state) = peer_states.iter_mut().find(|p| p.call == peer_call) {
                        if peer_state.phase == PeerPhase::Handshaking {
                            // Session will be disconnected separately
                            let _ = peer_state.failed(&err);
                        }
                    }

                    // For "loop prevention" errors, we're already connected via inbound
                    if err.contains("loop") || err.contains("Refusing") {
                        info!(
                            "Session {} refused due to loop prevention - using inbound connection instead",
                            session_id
                        );
                    }

                    // Disconnect the L4 session
                    let frames = session_mgr.disconnect(session_id);
                    for frame in frames {
                        transport.queue_frame(&frame)
                            .map_err(|e| anyhow::anyhow!("Queue error: {}", e))?;
                    }
                    transport.flush().await
                        .map_err(|e| anyhow::anyhow!("Flush error: {}", e))?;
                }
            }
        }
        Ok(())
    }

    /// Handle a parsed chat message
    async fn handle_chat_message(
        &mut self,
        session_id: &SessionId,
        msg: Message,
        _transport: &mut NetromTransport,  // Unused: flush happens in main loop
        session_mgr: &mut SessionManager,
        session_circuits: &HashMap<SessionId, crate::state::CircuitId>,
        client_senders: &ClientSenders,
    ) -> anyhow::Result<()> {
        Self::log_message(&msg);
        crate::metrics::CHAT_MESSAGES_RECEIVED
            .with_label_values(&[crate::metrics::message_label(&msg)])
            .inc();

        // Look up this session's circuit_id for proper node/user tracking
        let circuit_id = session_circuits.get(session_id).copied().unwrap_or(0);

        // Update state based on message type
        match &msg {
            Message::Join(j) => {
                let mut state = self.state.write().await;
                state.add_user(&j.user, &j.node, &j.name, &j.qth, circuit_id);
            }
            Message::Leave(l) => {
                let mut state = self.state.write().await;
                state.remove_user(&l.user, &l.node);
            }
            Message::Topic(t) => {
                let mut state = self.state.write().await;
                state.set_user_topic(&t.user, &t.node, &t.topic);
            }
            Message::NodeLink(nl) => {
                let mut state = self.state.write().await;
                state.add_node_route(circuit_id, &nl.new_node, &nl.alias, nl.version.clone());
            }
            Message::NodeUnlink(nu) => {
                let mut state = self.state.write().await;
                let removed = state.remove_users_on_node(&nu.lost_node);
                if !removed.is_empty() {
                    info!("NodeUnlink: removed {} users from lost node {}", removed.len(), nu.lost_node);
                }
            }
            _ => {}
        }

        // Broadcast to local clients
        broadcast_message_to_clients(client_senders, &msg).await;

        // Handle keepalive/poll responses - reply to sender, don't forward
        match &msg {
            Message::Keepalive(ka) => {
                let resp = ka.make_response(&self.config.node.call);
                let encoded = resp.encode();
                session_mgr.queue(session_id, &encoded);
                return Ok(());
            }
            Message::Poll(p) => {
                let resp = p.make_response(&self.config.node.call);
                let encoded = resp.encode();
                session_mgr.queue(session_id, &encoded);
                return Ok(());
            }
            Message::PollResponse(_) => {
                // Consume locally, don't forward
                return Ok(());
            }
            _ => {}
        }

        // Queue message for all other sessions (data batching)
        // Messages are buffered in session_mgr and flushed at strategic points
        // This allows multiple messages (like multiple joins) to be combined into fewer frames
        let msg_label = crate::metrics::message_label(&msg);
        let encoded = msg.encode();
        let connected = session_mgr.connected_sessions();
        let mut forward_count: u64 = 0;
        for other_id in connected {
            if other_id != *session_id {
                session_mgr.queue(&other_id, &encoded);
                forward_count += 1;
            }
        }
        if forward_count > 0 {
            crate::metrics::CHAT_MESSAGES_SENT
                .with_label_values(&[msg_label])
                .inc_by(forward_count);
        }
        // Note: Actual transmission happens in flush_queued_data() called from main loop

        Ok(())
    }

    /// Flush all queued session data to the transport
    ///
    /// This combines buffered messages into L4 frames and sends them.
    /// Called at the end of each event loop iteration to batch messages.
    async fn flush_queued_data(
        session_mgr: &mut SessionManager,
        transport: &mut NetromTransport,
    ) -> anyhow::Result<()> {
        // Get all queued data as frames
        let batched = session_mgr.flush_all();
        if batched.is_empty() {
            return Ok(());
        }

        // Queue all frames to transport
        for (_session_id, frames) in batched {
            for frame in frames {
                transport.queue_frame(&frame)
                    .map_err(|e| anyhow::anyhow!("Queue error: {}", e))?;
            }
        }

        // Flush all at once
        transport.flush().await
            .map_err(|e| anyhow::anyhow!("Flush error: {}", e))?;

        Ok(())
    }

    /// Handle client API event in NetROM mode
    async fn handle_netrom_client_event(
        &mut self,
        event: ClientApiEvent,
        our_call: &str,
        _transport: &mut NetromTransport,  // Unused: flush happens in main loop
        session_mgr: &mut SessionManager,
        client_senders: &ClientSenders,
        local_clients: &LocalClients,
    ) -> anyhow::Result<()> {
        match event {
            ClientApiEvent::Connected(client_id) => {
                info!("Local client {} connected", client_id);
                crate::metrics::CLIENTS_ACTIVE.inc();
            }

            ClientApiEvent::Command(client_id, cmd) => {
                let cmd_label = match &cmd {
                    ClientCommand::Join { .. } => "join",
                    ClientCommand::Leave => "leave",
                    ClientCommand::SendData { .. } => "send_data",
                    ClientCommand::SendPrivate { .. } => "send_private",
                    ClientCommand::SetTopic { .. } => "set_topic",
                    ClientCommand::SetInfo { .. } => "set_info",
                    ClientCommand::GetUsers => "get_users",
                    ClientCommand::GetNodes => "get_nodes",
                };
                crate::metrics::CLIENT_COMMANDS.with_label_values(&[cmd_label]).inc();
                let client_info = {
                    let clients = local_clients.read().await;
                    clients.get(&client_id).cloned()
                };

                match cmd {
                    ClientCommand::Join { user, name, qth } => {
                        // Update client state
                        {
                            let mut clients = local_clients.write().await;
                            if let Some(client) = clients.get_mut(&client_id) {
                                client.user = user.clone();
                                client.name = name.clone();
                                client.qth = qth.clone();
                                client.joined = true;
                            }
                        }

                        // Add to server state
                        {
                            let mut state = self.state.write().await;
                            state.add_user(&user, our_call, &name, &qth, 0);
                        }

                        // Create join message
                        let join_msg = Message::Join(crate::protocol::JoinMessage {
                            node: our_call.to_string(),
                            user: user.clone(),
                            name,
                            qth,
                        });

                        // Queue for all sessions (flush happens in main loop)
                        let encoded = join_msg.encode();
                        for session_id in session_mgr.connected_sessions() {
                            session_mgr.queue(&session_id, &encoded);
                        }

                        broadcast_message_to_clients(client_senders, &join_msg).await;
                        info!("Local client {} joined as {}", client_id, user);
                    }

                    ClientCommand::Leave => {
                        if let Some(client) = client_info {
                            if client.joined {
                                {
                                    let mut state = self.state.write().await;
                                    state.remove_user(&client.user, our_call);
                                }

                                let leave_msg = Message::Leave(crate::protocol::LeaveMessage {
                                    node: our_call.to_string(),
                                    user: client.user.clone(),
                                    name: client.name.clone(),
                                    qth: client.qth.clone(),
                                });

                                let encoded = leave_msg.encode();
                                for session_id in session_mgr.connected_sessions() {
                                    session_mgr.queue(&session_id, &encoded);
                                }

                                broadcast_message_to_clients(client_senders, &leave_msg).await;
                            }
                        }
                    }

                    ClientCommand::SendData { text } => {
                        if let Some(client) = client_info {
                            if client.joined {
                                let data_msg = Message::Data(crate::protocol::DataMessage {
                                    node: our_call.to_string(),
                                    user: client.user.clone(),
                                    text,
                                });

                                Self::log_message(&data_msg);

                                let encoded = data_msg.encode();
                                for session_id in session_mgr.connected_sessions() {
                                    session_mgr.queue(&session_id, &encoded);
                                }

                                broadcast_message_to_clients(client_senders, &data_msg).await;
                            }
                        }
                    }

                    ClientCommand::SendPrivate { to, text } => {
                        if let Some(client) = client_info {
                            if client.joined {
                                let private_msg = Message::Private(crate::protocol::PrivateMessage {
                                    node: our_call.to_string(),
                                    from: client.user.clone(),
                                    to,
                                    text,
                                });

                                Self::log_message(&private_msg);

                                let encoded = private_msg.encode();
                                for session_id in session_mgr.connected_sessions() {
                                    session_mgr.queue(&session_id, &encoded);
                                }

                                broadcast_message_to_clients(client_senders, &private_msg).await;
                            }
                        }
                    }

                    ClientCommand::SetTopic { topic } => {
                        if let Some(client) = client_info {
                            if client.joined {
                                {
                                    let mut clients = local_clients.write().await;
                                    if let Some(c) = clients.get_mut(&client_id) {
                                        c.topic = topic.clone();
                                    }
                                }

                                {
                                    let mut state = self.state.write().await;
                                    state.set_user_topic(&client.user, our_call, &topic);
                                }

                                let topic_msg = Message::Topic(crate::protocol::TopicMessage {
                                    node: our_call.to_string(),
                                    user: client.user.clone(),
                                    topic,
                                });

                                let encoded = topic_msg.encode();
                                for session_id in session_mgr.connected_sessions() {
                                    session_mgr.queue(&session_id, &encoded);
                                }

                                broadcast_message_to_clients(client_senders, &topic_msg).await;
                            }
                        }
                    }

                    ClientCommand::SetInfo { name, qth } => {
                        if let Some(client) = client_info {
                            if client.joined {
                                {
                                    let mut clients = local_clients.write().await;
                                    if let Some(c) = clients.get_mut(&client_id) {
                                        c.name = name.clone();
                                        c.qth = qth.clone();
                                    }
                                }

                                let info_msg = Message::Info(crate::protocol::InfoMessage {
                                    node: our_call.to_string(),
                                    user: client.user.clone(),
                                    name,
                                    qth,
                                });

                                let encoded = info_msg.encode();
                                for session_id in session_mgr.connected_sessions() {
                                    session_mgr.queue(&session_id, &encoded);
                                }

                                broadcast_message_to_clients(client_senders, &info_msg).await;
                            }
                        }
                    }

                    ClientCommand::GetUsers => {
                        let users: Vec<UserInfo> = {
                            let state = self.state.read().await;
                            state.users.values().map(UserInfo::from).collect()
                        };

                        let _ = send_to_client(client_senders, client_id, &ClientEvent::Users { users }).await;
                    }

                    ClientCommand::GetNodes => {
                        let nodes: Vec<NodeInfo> = {
                            let state = self.state.read().await;
                            state.nodes.values().map(|n| NodeInfo {
                                call: n.call.clone(),
                                alias: n.alias.clone(),
                                version: n.version.clone(),
                            }).collect()
                        };

                        let _ = send_to_client(client_senders, client_id, &ClientEvent::Nodes { nodes }).await;
                    }
                }
            }

            ClientApiEvent::Disconnected(client_id) => {
                crate::metrics::CLIENTS_ACTIVE.dec();
                let client_info = {
                    let mut clients = local_clients.write().await;
                    clients.remove(&client_id)
                };

                if let Some(client) = client_info {
                    if client.joined {
                        {
                            let mut state = self.state.write().await;
                            state.remove_user(&client.user, our_call);
                        }

                        let leave_msg = Message::Leave(crate::protocol::LeaveMessage {
                            node: our_call.to_string(),
                            user: client.user.clone(),
                            name: client.name.clone(),
                            qth: client.qth.clone(),
                        });

                        let encoded = leave_msg.encode();
                        for session_id in session_mgr.connected_sessions() {
                            session_mgr.queue(&session_id, &encoded);
                        }

                        broadcast_message_to_clients(client_senders, &leave_msg).await;
                        info!("Local client {} ({}) disconnected", client_id, client.user);
                    }
                }
            }
        }

        Ok(())
    }

    /// Log a message (without forwarding)
    fn log_message(message: &Message) {
        match message {
            Message::NodeLink(nl) => {
                info!("Node {} announces {} ({})", nl.node, nl.new_node, nl.alias);
            }
            Message::NodeUnlink(nu) => {
                info!("Node {} lost {}", nu.node, nu.lost_node);
            }
            Message::Join(j) => {
                info!("User {} joined on node {} ({} @ {})", j.user, j.node, j.name, j.qth);
            }
            Message::Leave(l) => {
                info!("User {} left on node {}", l.user, l.node);
            }
            Message::Data(d) => {
                info!("[{}@{}] {}", d.user, d.node, d.text);
            }
            Message::Private(p) => {
                info!("Private from {} to {}: {}", p.from, p.to, p.text);
            }
            Message::Topic(t) => {
                info!("User {} changed to topic {}", t.user, t.topic);
            }
            Message::Info(i) => {
                debug!("User info update: {} on {}", i.user, i.node);
            }
            Message::Keepalive(k) => {
                debug!("Keepalive from {} to {}", k.src_node, k.dest_node);
            }
            Message::Poll(p) => {
                debug!("Poll from {} to {}", p.src_node, p.dest_node);
            }
            Message::PollResponse(p) => {
                debug!("Poll response from {} to {}", p.src_node, p.dest_node);
            }
        }
    }
}
