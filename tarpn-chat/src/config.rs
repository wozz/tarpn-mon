//! Configuration for the chat server

use serde::Deserialize;
use std::path::Path;
use anyhow::Result;

/// Main server configuration
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Our node identity on the chat network
    pub node: NodeConfig,

    /// NetROM over TCP configuration (primary mode)
    #[serde(default)]
    pub netrom: Option<NetromConfig>,

    /// Client API for local WebSocket clients (tarpn-mon backend)
    #[serde(default)]
    pub client: Option<ClientApiConfig>,

    /// Peer chat nodes we connect to (outbound L4 connections)
    #[serde(default)]
    pub peers: Vec<PeerConfig>,

    /// Known nodes with their chat aliases (like LinBPQ's OtherNodes)
    /// Used to announce correct aliases for inbound connections
    #[serde(default)]
    pub known_nodes: Vec<KnownNodeConfig>,

    /// Prometheus metrics endpoint
    #[serde(default)]
    pub metrics: Option<MetricsConfig>,
}

/// NetROM over TCP configuration
///
/// tarpn-chat operates as a peer node connected to LinBPQ via NETROMPORT.
#[derive(Debug, Clone, Deserialize)]
pub struct NetromConfig {
    /// LinBPQ's NETROMPORT address to connect to (e.g., "127.0.0.1:63119")
    #[serde(default)]
    pub linbpq: Option<String>,

    /// Address to listen on for LinBPQ connections (e.g., "0.0.0.0:63120")
    #[serde(default)]
    pub listen: Option<String>,

    /// L4 window size (max unacked frames)
    #[serde(default = "default_window")]
    pub window: u8,

    /// Session inactivity timeout in seconds (default 15 min like LinBPQ's L4LIMIT)
    #[serde(default = "default_session_timeout")]
    pub timeout: u64,

    /// T1 retransmission timeout in seconds (default 120s to match TARPN's L4TIMEOUT)
    #[serde(default = "default_t1_timeout")]
    pub t1: u64,
}

fn default_window() -> u8 {
    3 // TARPN's L4WINDOW value
}

fn default_session_timeout() -> u64 {
    900 // 15 minutes like LinBPQ's L4LIMIT
}

fn default_t1_timeout() -> u64 {
    120 // TARPN's L4TIMEOUT value - accounts for multi-hop RF latency
}

/// Prometheus metrics configuration
#[derive(Debug, Clone, Deserialize)]
pub struct MetricsConfig {
    /// HTTP port for metrics endpoint
    #[serde(default = "default_metrics_port")]
    pub port: u16,

    /// Address to bind to
    #[serde(default = "default_metrics_bind")]
    pub bind: String,
}

fn default_metrics_port() -> u16 {
    18212
}

fn default_metrics_bind() -> String {
    "0.0.0.0".to_string()
}

/// Known node configuration (equivalent to LinBPQ's OtherChatNodes)
/// Specifies the chat alias for nodes that may connect to us
#[derive(Debug, Clone, Deserialize)]
pub struct KnownNodeConfig {
    /// Node's callsign (e.g., "TEST7-9")
    pub call: String,

    /// Node's chat alias (e.g., "T7CHAT")
    pub alias: String,
}

/// Configuration for a peer chat node
/// Supports direct TCP connection for NetROM
#[derive(Debug, Clone, Deserialize)]
pub struct PeerConfig {
    /// Peer's callsign (e.g., "TEST4-9")
    pub call: String,

    /// Peer's alias (optional, for display)
    pub alias: Option<String>,

    /// Host to connect to (IP or hostname) - for direct TCP mode
    /// If not specified, connection is disabled unless listening
    pub host: Option<String>,

    /// Port to connect to (peer's listener port) - for direct TCP mode
    #[serde(default = "default_peer_port")]
    pub port: u16,

    /// Auto-reconnect on disconnect
    #[serde(default = "default_true")]
    pub auto_reconnect: bool,

    /// Reconnect delay in seconds
    #[serde(default = "default_reconnect_delay")]
    pub reconnect_delay: u64,
}

impl PeerConfig {
    /// Check if this peer has a valid connection method
    pub fn is_enabled(&self) -> bool {
        self.host.is_some()
    }
}

fn default_peer_port() -> u16 {
    63005
}

/// Client API configuration for local WebSocket clients
/// This enables tarpn-mon (or other local apps) to connect via JSON WebSocket
#[derive(Debug, Clone, Deserialize)]
pub struct ClientApiConfig {
    /// TCP port for WebSocket server
    pub port: u16,

    /// Address to bind to
    #[serde(default = "default_bind")]
    pub bind: String,

    /// Maximum number of local clients (default 10)
    #[serde(default = "default_max_clients")]
    pub max_clients: usize,
}

fn default_max_clients() -> usize {
    10
}

fn default_bind() -> String {
    "127.0.0.1".to_string()
}

/// Our node identity on the chat network
#[derive(Debug, Clone, Deserialize)]
pub struct NodeConfig {
    /// Our callsign as a chat node (e.g., "BOT" or "WA2M-9")
    pub call: String,

    /// Our alias (e.g., "CHTBOT")
    pub alias: String,
}

fn default_true() -> bool {
    true
}

fn default_reconnect_delay() -> u64 {
    30
}

impl Config {
    /// Load configuration from a TOML file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    /// Check if NetROM mode is configured
    pub fn is_netrom_mode(&self) -> bool {
        self.netrom.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_client_api_config() {
        let toml = r#"
[node]
call = "WA2M-10"
alias = "MYCHAT"

[client]
port = 8513
bind = "0.0.0.0"
max_clients = 5
"#;
        let config: Config = toml::from_str(toml).unwrap();
        let client = config.client.unwrap();
        assert_eq!(client.port, 8513);
        assert_eq!(client.bind, "0.0.0.0");
        assert_eq!(client.max_clients, 5);
    }

    #[test]
    fn test_parse_client_api_defaults() {
        let toml = r#"
[node]
call = "WA2M-10"
alias = "MYCHAT"

[client]
port = 8513
"#;
        let config: Config = toml::from_str(toml).unwrap();
        let client = config.client.unwrap();
        assert_eq!(client.port, 8513);
        assert_eq!(client.bind, "127.0.0.1"); // default
        assert_eq!(client.max_clients, 10); // default
    }

    #[test]
    fn test_parse_peer_direct_tcp() {
        let toml = r#"
[node]
call = "TEST5-9"
alias = "T5CHAT"

[[peers]]
call = "TEST4-9"
alias = "T4CHAT"
host = "192.168.1.100"
port = 63005
"#;
        let config: Config = toml::from_str(toml).unwrap();
        assert_eq!(config.peers.len(), 1);
        let peer = &config.peers[0];
        assert_eq!(peer.call, "TEST4-9");
        assert_eq!(peer.host, Some("192.168.1.100".to_string()));
    }
}
#[test]
fn tarpn_chat_module_config_yields_dialable_peers() {
    // Exactly what tarpn-node/modules/tarpn-chat/hooks/configure writes.
    // Peers must land in [[peers]]: that is the only list the server dials.
    // [[known_nodes]] supplies aliases for announcing sessions, so a config
    // with the peers in that section alone connects to LinBPQ and then sits
    // there doing nothing, which looks exactly like a radio fault.
    let text = r#"
# Managed by the tarpn-chat module
[node]
call = "WA2M-9"
alias = "ZA2M09"

[netrom]
linbpq = "127.0.0.1:63119"

[client]
port = 8513
bind = "127.0.0.1"
max_clients = 10

[[peers]]
call = "N2IRZ-9"

[[peers]]
call = "TEST1-9"
alias = "T1CHAT"

[[known_nodes]]
call = "TEST1-9"
alias = "T1CHAT"
"#;

    let cfg: Config = toml::from_str(text).expect("module-generated config must parse");
    assert_eq!(cfg.node.call, "WA2M-9");
    assert_eq!(
        cfg.peers.len(),
        2,
        "peers drive outbound connections; without them the node dials nobody"
    );
    assert_eq!(cfg.peers[0].call, "N2IRZ-9");
    assert!(cfg.peers[0].alias.is_none(), "alias is optional for a derived peer");
    assert_eq!(cfg.known_nodes.len(), 1);
}
