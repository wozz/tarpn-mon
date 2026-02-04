//! Prometheus metrics for tarpn-chat
//!
//! Exposes counters and gauges on a configurable HTTP port.
//! GET /metrics returns Prometheus text exposition format.

use lazy_static::lazy_static;
use prometheus::{
    Encoder, IntCounter, IntCounterVec, IntGauge, IntGaugeVec, TextEncoder,
    opts, register_int_counter, register_int_counter_vec,
    register_int_gauge, register_int_gauge_vec,
};
use std::net::SocketAddr;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;
use tracing::{info, warn};

lazy_static! {
    // ============================================================
    // NetROM L4 Counters
    // ============================================================

    /// L4 frames sent, labeled by opcode
    pub static ref NETROM_FRAMES_SENT: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_netrom_frames_sent_total", "NetROM L4 frames sent"),
        &["opcode"]
    ).unwrap();

    /// L4 frames received, labeled by opcode
    pub static ref NETROM_FRAMES_RECEIVED: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_netrom_frames_received_total", "NetROM L4 frames received"),
        &["opcode"]
    ).unwrap();

    /// Frame retransmissions
    pub static ref NETROM_RETRANSMISSIONS: IntCounter = register_int_counter!(
        "tarpn_chat_netrom_retransmissions_total", "NetROM frame retransmissions"
    ).unwrap();

    /// NAK frames sent (gap detected)
    pub static ref NETROM_NAKS_SENT: IntCounter = register_int_counter!(
        "tarpn_chat_netrom_naks_sent_total", "NAK frames sent due to sequence gaps"
    ).unwrap();

    /// Duplicate frames received
    pub static ref NETROM_DUPLICATES: IntCounter = register_int_counter!(
        "tarpn_chat_netrom_duplicate_frames_total", "Duplicate frames received and discarded"
    ).unwrap();

    // ============================================================
    // Session Gauges/Counters
    // ============================================================

    /// Currently active L4 sessions
    pub static ref SESSIONS_ACTIVE: IntGauge = register_int_gauge!(
        "tarpn_chat_sessions_active", "Number of active L4 sessions"
    ).unwrap();

    /// Sessions created, labeled by direction
    pub static ref SESSIONS_CREATED: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_sessions_created_total", "L4 sessions created"),
        &["direction"]
    ).unwrap();

    /// Sessions destroyed, labeled by reason
    pub static ref SESSIONS_DESTROYED: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_sessions_destroyed_total", "L4 sessions destroyed"),
        &["reason"]
    ).unwrap();

    // ============================================================
    // Transport Counters
    // ============================================================

    /// TCP bytes sent
    pub static ref TRANSPORT_BYTES_SENT: IntCounter = register_int_counter!(
        "tarpn_chat_transport_bytes_sent_total", "TCP bytes sent to LinBPQ"
    ).unwrap();

    /// TCP bytes received
    pub static ref TRANSPORT_BYTES_RECEIVED: IntCounter = register_int_counter!(
        "tarpn_chat_transport_bytes_received_total", "TCP bytes received from LinBPQ"
    ).unwrap();

    /// TCP connections established
    pub static ref TRANSPORT_TCP_CONNECTS: IntCounter = register_int_counter!(
        "tarpn_chat_transport_tcp_connects_total", "TCP connections established"
    ).unwrap();

    /// TCP disconnections
    pub static ref TRANSPORT_TCP_DISCONNECTS: IntCounter = register_int_counter!(
        "tarpn_chat_transport_tcp_disconnects_total", "TCP disconnections"
    ).unwrap();

    // ============================================================
    // Chat Protocol Counters
    // ============================================================

    /// Chat messages received from peers, labeled by type
    pub static ref CHAT_MESSAGES_RECEIVED: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_messages_received_total", "Chat protocol messages received"),
        &["type"]
    ).unwrap();

    /// Chat messages sent to peers, labeled by type
    pub static ref CHAT_MESSAGES_SENT: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_messages_sent_total", "Chat protocol messages sent"),
        &["type"]
    ).unwrap();

    /// Successful chat handshakes
    pub static ref CHAT_HANDSHAKES_COMPLETED: IntCounter = register_int_counter!(
        "tarpn_chat_handshakes_completed_total", "Successful chat handshakes"
    ).unwrap();

    /// Failed chat handshakes
    pub static ref CHAT_HANDSHAKES_FAILED: IntCounter = register_int_counter!(
        "tarpn_chat_handshakes_failed_total", "Failed chat handshakes"
    ).unwrap();

    // ============================================================
    // Client API Gauges/Counters
    // ============================================================

    /// Connected WebSocket clients
    pub static ref CLIENTS_ACTIVE: IntGauge = register_int_gauge!(
        "tarpn_chat_clients_active", "Number of connected WebSocket clients"
    ).unwrap();

    /// Client API commands received, labeled by command type
    pub static ref CLIENT_COMMANDS: IntCounterVec = register_int_counter_vec!(
        opts!("tarpn_chat_client_commands_total", "Client API commands received"),
        &["command"]
    ).unwrap();

    // ============================================================
    // Peer Connection Gauges
    // ============================================================

    /// Peer connection status (1=connected, 0=disconnected)
    pub static ref PEERS_CONNECTED: IntGaugeVec = register_int_gauge_vec!(
        opts!("tarpn_chat_peer_connected", "Peer connection status"),
        &["peer"]
    ).unwrap();
}

/// Map L4Opcode to a label string for metrics
pub fn opcode_label(opcode: &crate::netrom::L4Opcode) -> &'static str {
    use crate::netrom::L4Opcode;
    match opcode {
        L4Opcode::ConnectRequest => "creq",
        L4Opcode::ConnectAck => "cack",
        L4Opcode::DisconnectRequest => "dreq",
        L4Opcode::DisconnectAck => "dack",
        L4Opcode::Information => "info",
        L4Opcode::InformationAck => "iack",
        L4Opcode::Reset => "reset",
        L4Opcode::ConnectRequestEx => "creq_ex",
    }
}

/// Map chat Message to a type label for metrics
pub fn message_label(msg: &crate::protocol::Message) -> &'static str {
    use crate::protocol::Message;
    match msg {
        Message::Join(_) => "join",
        Message::Leave(_) => "leave",
        Message::Data(_) => "data",
        Message::Private(_) => "private",
        Message::Topic(_) => "topic",
        Message::Info(_) => "info",
        Message::NodeLink(_) => "nodelink",
        Message::NodeUnlink(_) => "nodeunlink",
        Message::Keepalive(_) => "keepalive",
        Message::Poll(_) => "poll",
        Message::PollResponse(_) => "poll_response",
    }
}

/// Start the metrics HTTP server
///
/// Serves GET /metrics in Prometheus text exposition format.
pub async fn serve_metrics(bind: &str, port: u16) -> anyhow::Result<()> {
    let addr: SocketAddr = format!("{}:{}", bind, port).parse()?;
    let listener = TcpListener::bind(addr).await?;
    info!("Metrics server listening on http://{}/metrics", addr);

    loop {
        match listener.accept().await {
            Ok((mut stream, _peer)) => {
                tokio::spawn(async move {
                    // Read the request (minimal: just consume headers)
                    let mut buf = [0u8; 1024];
                    let _ = tokio::io::AsyncReadExt::read(&mut stream, &mut buf).await;

                    let request = String::from_utf8_lossy(&buf);
                    if request.starts_with("GET /metrics") {
                        let encoder = TextEncoder::new();
                        let metric_families = prometheus::gather();
                        let mut body = Vec::new();
                        encoder.encode(&metric_families, &mut body).unwrap();

                        let response = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                            body.len()
                        );
                        let _ = stream.write_all(response.as_bytes()).await;
                        let _ = stream.write_all(&body).await;
                    } else {
                        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                        let _ = stream.write_all(response.as_bytes()).await;
                    }
                });
            }
            Err(e) => {
                warn!("Metrics accept error: {}", e);
            }
        }
    }
}
