//! WebSocket API for local clients (e.g., tarpn-mon Go backend)
//!
//! This module provides a JSON-based WebSocket interface for local applications
//! to connect to the chat server. Unlike the binary LinBPQ protocol used for
//! inter-node communication, this API uses human-readable JSON messages.
//!
//! Local clients appear as "virtual users" on the chat network - they are
//! announced with Join messages and tracked in the server state.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, RwLock};
use tokio_tungstenite::{accept_async, tungstenite::Message as WsMessage};
use tracing::{debug, error, info, warn};

use crate::protocol::{
    self, DataMessage, InfoMessage, JoinMessage, LeaveMessage, PrivateMessage, TopicMessage,
};
use crate::state::User;

/// Unique identifier for a local client connection
pub type ClientId = u64;

/// Global counter for generating unique client IDs
static NEXT_CLIENT_ID: AtomicU64 = AtomicU64::new(1);

/// Generate the next unique client ID
fn next_client_id() -> ClientId {
    NEXT_CLIENT_ID.fetch_add(1, Ordering::SeqCst)
}

/// Channel sender type for sending JSON strings to a client
pub type ClientSender = mpsc::Sender<String>;

/// Map of client IDs to their message senders
pub type ClientSenders = Arc<RwLock<HashMap<ClientId, ClientSender>>>;

/// Create a new empty client senders map
pub fn new_client_senders() -> ClientSenders {
    Arc::new(RwLock::new(HashMap::new()))
}

// ============================================================================
// JSON Protocol Types - Server to Client
// ============================================================================

/// Events sent from server to client (JSON)
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientEvent {
    /// User joined the chat
    Join {
        node: String,
        user: String,
        name: String,
        qth: String,
    },

    /// User left the chat
    Leave {
        node: String,
        user: String,
        name: String,
        qth: String,
    },

    /// Broadcast message
    Data {
        node: String,
        user: String,
        text: String,
    },

    /// Private message
    Private {
        node: String,
        from: String,
        to: String,
        text: String,
    },

    /// User changed topic
    Topic {
        node: String,
        user: String,
        topic: String,
    },

    /// User info update
    Info {
        node: String,
        user: String,
        name: String,
        qth: String,
    },

    /// Node linked to network
    NodeLink {
        node: String,
        new_node: String,
        alias: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        version: Option<String>,
    },

    /// Node unlinked from network
    NodeUnlink {
        node: String,
        lost_node: String,
    },

    /// Connection established
    Connected,

    /// Connection lost
    Disconnected {
        reason: String,
    },

    /// Response to get_users command
    Users {
        users: Vec<UserInfo>,
    },

    /// Response to get_nodes command
    Nodes {
        nodes: Vec<NodeInfo>,
    },

    /// Error message
    Error {
        message: String,
    },
}

/// User information for users response
#[derive(Debug, Clone, Serialize)]
pub struct UserInfo {
    pub call: String,
    pub name: String,
    pub node: String,
    pub qth: String,
    pub topic: String,
}

impl From<&User> for UserInfo {
    fn from(user: &User) -> Self {
        Self {
            call: user.call.clone(),
            name: user.name.clone(),
            node: user.node_call.clone(),
            qth: user.qth.clone(),
            topic: user.topic.clone(),
        }
    }
}

/// Node information for nodes response
#[derive(Debug, Clone, Serialize)]
pub struct NodeInfo {
    pub call: String,
    pub alias: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
}

// ============================================================================
// JSON Protocol Types - Client to Server
// ============================================================================

/// Commands received from client (JSON)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum ClientCommand {
    /// Announce as a user on the network
    Join {
        user: String,
        name: String,
        qth: String,
    },

    /// Leave the chat
    Leave,

    /// Send a broadcast message
    SendData {
        text: String,
    },

    /// Send a private message
    SendPrivate {
        to: String,
        text: String,
    },

    /// Change topic
    SetTopic {
        topic: String,
    },

    /// Update user info (name/qth)
    SetInfo {
        name: String,
        qth: String,
    },

    /// Request list of users
    GetUsers,

    /// Request list of nodes
    GetNodes,
}

// ============================================================================
// Protocol Message Conversion
// ============================================================================

/// Convert a protocol Message to a ClientEvent for JSON serialization
pub fn message_to_client_event(msg: &protocol::Message) -> Option<ClientEvent> {
    match msg {
        protocol::Message::Join(m) => Some(ClientEvent::Join {
            node: m.node.clone(),
            user: m.user.clone(),
            name: m.name.clone(),
            qth: m.qth.clone(),
        }),
        protocol::Message::Leave(m) => Some(ClientEvent::Leave {
            node: m.node.clone(),
            user: m.user.clone(),
            name: m.name.clone(),
            qth: m.qth.clone(),
        }),
        protocol::Message::Data(m) => Some(ClientEvent::Data {
            node: m.node.clone(),
            user: m.user.clone(),
            text: m.text.clone(),
        }),
        protocol::Message::Private(m) => Some(ClientEvent::Private {
            node: m.node.clone(),
            from: m.from.clone(),
            to: m.to.clone(),
            text: m.text.clone(),
        }),
        protocol::Message::Topic(m) => Some(ClientEvent::Topic {
            node: m.node.clone(),
            user: m.user.clone(),
            topic: m.topic.clone(),
        }),
        protocol::Message::Info(m) => Some(ClientEvent::Info {
            node: m.node.clone(),
            user: m.user.clone(),
            name: m.name.clone(),
            qth: m.qth.clone(),
        }),
        protocol::Message::NodeLink(m) => Some(ClientEvent::NodeLink {
            node: m.node.clone(),
            new_node: m.new_node.clone(),
            alias: m.alias.clone(),
            version: m.version.clone(),
        }),
        protocol::Message::NodeUnlink(m) => Some(ClientEvent::NodeUnlink {
            node: m.node.clone(),
            lost_node: m.lost_node.clone(),
        }),
        // Keepalive, Poll, PollResponse are internal - don't forward to clients
        protocol::Message::Keepalive(_)
        | protocol::Message::Poll(_)
        | protocol::Message::PollResponse(_) => None,
    }
}

/// Convert a ClientCommand to protocol Messages
/// Returns the messages to forward to the network
pub fn command_to_messages(
    cmd: &ClientCommand,
    our_node: &str,
    client_user: &str,
    client_name: &str,
    client_qth: &str,
    _client_topic: &str,
) -> Vec<protocol::Message> {
    match cmd {
        ClientCommand::Join { user, name, qth } => {
            vec![protocol::Message::Join(JoinMessage {
                node: our_node.to_string(),
                user: user.clone(),
                name: name.clone(),
                qth: qth.clone(),
            })]
        }
        ClientCommand::Leave => {
            vec![protocol::Message::Leave(LeaveMessage {
                node: our_node.to_string(),
                user: client_user.to_string(),
                name: client_name.to_string(),
                qth: client_qth.to_string(),
            })]
        }
        ClientCommand::SendData { text } => {
            vec![protocol::Message::Data(DataMessage {
                node: our_node.to_string(),
                user: client_user.to_string(),
                text: text.clone(),
            })]
        }
        ClientCommand::SendPrivate { to, text } => {
            vec![protocol::Message::Private(PrivateMessage {
                node: our_node.to_string(),
                from: client_user.to_string(),
                to: to.clone(),
                text: text.clone(),
            })]
        }
        ClientCommand::SetTopic { topic } => {
            vec![protocol::Message::Topic(TopicMessage {
                node: our_node.to_string(),
                user: client_user.to_string(),
                topic: topic.clone(),
            })]
        }
        ClientCommand::SetInfo { name, qth } => {
            vec![protocol::Message::Info(InfoMessage {
                node: our_node.to_string(),
                user: client_user.to_string(),
                name: name.clone(),
                qth: qth.clone(),
            })]
        }
        // These commands don't generate network messages
        ClientCommand::GetUsers | ClientCommand::GetNodes => vec![],
    }
}

// ============================================================================
// Local Client State
// ============================================================================

/// Represents a connected local client
#[derive(Debug, Clone)]
pub struct LocalClient {
    pub id: ClientId,
    pub user: String,
    pub name: String,
    pub qth: String,
    pub topic: String,
    pub joined: bool,
}

impl LocalClient {
    pub fn new(id: ClientId) -> Self {
        Self {
            id,
            user: String::new(),
            name: String::new(),
            qth: String::new(),
            topic: "General".to_string(),
            joined: false,
        }
    }
}

/// Map of client IDs to their state
pub type LocalClients = Arc<RwLock<HashMap<ClientId, LocalClient>>>;

/// Create a new empty local clients map
pub fn new_local_clients() -> LocalClients {
    Arc::new(RwLock::new(HashMap::new()))
}

// ============================================================================
// Internal Events (Client API -> Server)
// ============================================================================

/// Events sent from client connections to the central server loop
#[derive(Debug)]
pub enum ClientApiEvent {
    /// Client connected
    Connected(ClientId),

    /// Client sent a command
    Command(ClientId, ClientCommand),

    /// Client disconnected
    Disconnected(ClientId),
}

// ============================================================================
// WebSocket Server
// ============================================================================

/// Run the client API WebSocket server
pub async fn run_client_api_server(
    bind_addr: SocketAddr,
    event_tx: mpsc::Sender<ClientApiEvent>,
    client_senders: ClientSenders,
    local_clients: LocalClients,
) -> anyhow::Result<()> {
    let listener = TcpListener::bind(bind_addr).await?;
    info!("Client API listening on ws://{}", bind_addr);

    loop {
        match listener.accept().await {
            Ok((stream, peer_addr)) => {
                let client_id = next_client_id();
                info!("Client {} connected from {}", client_id, peer_addr);

                let event_tx = event_tx.clone();
                let client_senders = client_senders.clone();
                let local_clients = local_clients.clone();

                tokio::spawn(async move {
                    if let Err(e) = handle_client_connection(
                        client_id,
                        stream,
                        event_tx,
                        client_senders,
                        local_clients,
                    )
                    .await
                    {
                        error!("Client {} error: {}", client_id, e);
                    }
                });
            }
            Err(e) => {
                error!("Failed to accept connection: {}", e);
            }
        }
    }
}

/// Handle a single client WebSocket connection
async fn handle_client_connection(
    client_id: ClientId,
    stream: TcpStream,
    event_tx: mpsc::Sender<ClientApiEvent>,
    client_senders: ClientSenders,
    local_clients: LocalClients,
) -> anyhow::Result<()> {
    // Upgrade to WebSocket
    let ws_stream = accept_async(stream).await?;
    let (mut ws_sink, mut ws_stream) = ws_stream.split();

    // Create channel for outgoing messages
    let (outgoing_tx, mut outgoing_rx) = mpsc::channel::<String>(256);

    // Register client
    {
        let mut senders = client_senders.write().await;
        senders.insert(client_id, outgoing_tx);
    }
    {
        let mut clients = local_clients.write().await;
        clients.insert(client_id, LocalClient::new(client_id));
    }

    // Notify server of connection
    let _ = event_tx.send(ClientApiEvent::Connected(client_id)).await;

    // Send connected event to client
    let connected_event = serde_json::to_string(&ClientEvent::Connected)?;
    ws_sink.send(WsMessage::Text(connected_event.into())).await?;

    // Run bidirectional message loop
    loop {
        tokio::select! {
            // Incoming message from client
            msg = ws_stream.next() => {
                match msg {
                    Some(Ok(WsMessage::Text(text))) => {
                        debug!("Client {} received: {}", client_id, text);
                        match serde_json::from_str::<ClientCommand>(&text) {
                            Ok(cmd) => {
                                let _ = event_tx.send(ClientApiEvent::Command(client_id, cmd)).await;
                            }
                            Err(e) => {
                                warn!("Client {} invalid command: {}", client_id, e);
                                let error_event = serde_json::to_string(&ClientEvent::Error {
                                    message: format!("Invalid command: {}", e),
                                })?;
                                ws_sink.send(WsMessage::Text(error_event.into())).await?;
                            }
                        }
                    }
                    Some(Ok(WsMessage::Close(_))) => {
                        debug!("Client {} sent close", client_id);
                        break;
                    }
                    Some(Ok(WsMessage::Ping(data))) => {
                        ws_sink.send(WsMessage::Pong(data)).await?;
                    }
                    Some(Ok(_)) => {
                        // Ignore other message types (Binary, Pong, Frame)
                    }
                    Some(Err(e)) => {
                        warn!("Client {} WebSocket error: {}", client_id, e);
                        break;
                    }
                    None => {
                        debug!("Client {} stream ended", client_id);
                        break;
                    }
                }
            }

            // Outgoing message to client
            msg = outgoing_rx.recv() => {
                match msg {
                    Some(json) => {
                        if let Err(e) = ws_sink.send(WsMessage::Text(json.into())).await {
                            warn!("Client {} send error: {}", client_id, e);
                            break;
                        }
                    }
                    None => {
                        // Channel closed
                        break;
                    }
                }
            }
        }
    }

    // Cleanup
    {
        let mut senders = client_senders.write().await;
        senders.remove(&client_id);
    }
    {
        let mut clients = local_clients.write().await;
        clients.remove(&client_id);
    }

    // Notify server of disconnection
    let _ = event_tx.send(ClientApiEvent::Disconnected(client_id)).await;

    info!("Client {} disconnected", client_id);
    Ok(())
}

/// Send an event to a specific client
pub async fn send_to_client(
    client_senders: &ClientSenders,
    client_id: ClientId,
    event: &ClientEvent,
) -> Result<(), String> {
    let json = serde_json::to_string(event).map_err(|e| e.to_string())?;
    let senders = client_senders.read().await;
    if let Some(sender) = senders.get(&client_id) {
        sender
            .send(json)
            .await
            .map_err(|e| format!("Send failed: {}", e))
    } else {
        Err("Client not found".to_string())
    }
}

/// Broadcast an event to all connected clients
pub async fn broadcast_to_clients(client_senders: &ClientSenders, event: &ClientEvent) {
    let json = match serde_json::to_string(event) {
        Ok(j) => j,
        Err(e) => {
            error!("Failed to serialize event: {}", e);
            return;
        }
    };

    let senders = client_senders.read().await;
    for (client_id, sender) in senders.iter() {
        if let Err(e) = sender.send(json.clone()).await {
            warn!("Failed to send to client {}: {}", client_id, e);
        }
    }
}

/// Broadcast a protocol message to all connected clients (converts to JSON)
pub async fn broadcast_message_to_clients(
    client_senders: &ClientSenders,
    msg: &protocol::Message,
) {
    if let Some(event) = message_to_client_event(msg) {
        broadcast_to_clients(client_senders, &event).await;
    }
}

/// Broadcast a protocol message to all connected clients except one (converts to JSON)
/// Used to avoid echoing messages back to the sender
pub async fn broadcast_message_to_clients_except(
    client_senders: &ClientSenders,
    msg: &protocol::Message,
    exclude_client: ClientId,
) {
    let event = match message_to_client_event(msg) {
        Some(e) => e,
        None => return,
    };

    let json = match serde_json::to_string(&event) {
        Ok(j) => j,
        Err(e) => {
            error!("Failed to serialize event: {}", e);
            return;
        }
    };

    let senders = client_senders.read().await;
    for (client_id, sender) in senders.iter() {
        if *client_id != exclude_client {
            if let Err(e) = sender.send(json.clone()).await {
                warn!("Failed to send to client {}: {}", client_id, e);
            }
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_to_client_event_data() {
        let msg = protocol::Message::Data(DataMessage {
            node: "WA2M-9".into(),
            user: "N0CALL".into(),
            text: "Hello!".into(),
        });
        let event = message_to_client_event(&msg).unwrap();
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"type\":\"data\""));
        assert!(json.contains("\"node\":\"WA2M-9\""));
        assert!(json.contains("\"user\":\"N0CALL\""));
        assert!(json.contains("\"text\":\"Hello!\""));
    }

    #[test]
    fn test_message_to_client_event_join() {
        let msg = protocol::Message::Join(JoinMessage {
            node: "WA2M-9".into(),
            user: "N0CALL".into(),
            name: "John".into(),
            qth: "Home".into(),
        });
        let event = message_to_client_event(&msg).unwrap();
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"type\":\"join\""));
        assert!(json.contains("\"name\":\"John\""));
    }

    #[test]
    fn test_message_to_client_event_keepalive_none() {
        let msg = protocol::Message::Keepalive(protocol::KeepaliveMessage {
            src_node: "WA2M-9".into(),
            dest_node: "KB1ABC".into(),
            version: None,
        });
        // Keepalive should not be forwarded to clients
        assert!(message_to_client_event(&msg).is_none());
    }

    #[test]
    fn test_parse_client_command_send_data() {
        let json = r#"{"cmd": "send_data", "text": "Hello everyone!"}"#;
        let cmd: ClientCommand = serde_json::from_str(json).unwrap();
        match cmd {
            ClientCommand::SendData { text } => assert_eq!(text, "Hello everyone!"),
            _ => panic!("Wrong command type"),
        }
    }

    #[test]
    fn test_parse_client_command_join() {
        let json = r#"{"cmd": "join", "user": "N0CALL", "name": "John", "qth": "Home"}"#;
        let cmd: ClientCommand = serde_json::from_str(json).unwrap();
        match cmd {
            ClientCommand::Join { user, name, qth } => {
                assert_eq!(user, "N0CALL");
                assert_eq!(name, "John");
                assert_eq!(qth, "Home");
            }
            _ => panic!("Wrong command type"),
        }
    }

    #[test]
    fn test_parse_client_command_get_users() {
        let json = r#"{"cmd": "get_users"}"#;
        let cmd: ClientCommand = serde_json::from_str(json).unwrap();
        assert!(matches!(cmd, ClientCommand::GetUsers));
    }

    #[test]
    fn test_command_to_messages_send_data() {
        let cmd = ClientCommand::SendData {
            text: "Hello!".into(),
        };
        let messages = command_to_messages(&cmd, "WA2M-9", "N0CALL", "John", "Home", "General");
        assert_eq!(messages.len(), 1);
        match &messages[0] {
            protocol::Message::Data(m) => {
                assert_eq!(m.node, "WA2M-9");
                assert_eq!(m.user, "N0CALL");
                assert_eq!(m.text, "Hello!");
            }
            _ => panic!("Wrong message type"),
        }
    }

    #[test]
    fn test_serialize_users_response() {
        let event = ClientEvent::Users {
            users: vec![
                UserInfo {
                    call: "N0CALL".into(),
                    name: "John".into(),
                    node: "WA2M-9".into(),
                    qth: "Home".into(),
                    topic: "General".into(),
                },
            ],
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"type\":\"users\""));
        assert!(json.contains("\"call\":\"N0CALL\""));
    }

    #[test]
    fn test_serialize_node_link() {
        let event = ClientEvent::NodeLink {
            node: "WA2M-9".into(),
            new_node: "KB1ABC".into(),
            alias: "RDGCHT".into(),
            version: Some("1.0.0".into()),
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"type\":\"node_link\""));
        assert!(json.contains("\"new_node\":\"KB1ABC\""));
        assert!(json.contains("\"version\":\"1.0.0\""));
    }

    #[test]
    fn test_serialize_node_link_no_version() {
        let event = ClientEvent::NodeLink {
            node: "WA2M-9".into(),
            new_node: "KB1ABC".into(),
            alias: "RDGCHT".into(),
            version: None,
        };
        let json = serde_json::to_string(&event).unwrap();
        // version should be omitted when None
        assert!(!json.contains("version"));
    }
}
