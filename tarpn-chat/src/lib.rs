//! TARPN Chat - LinBPQ-compatible chat node implementation
//!
//! This library implements the LinBPQ chat protocol for participation in the
//! amateur radio chat mesh network. The node connects to LinBPQ via NetROM over
//! TCP, enabling bidirectional L4 connections with its own callsign.

pub mod client_api;
pub mod config;
pub mod metrics;
pub mod netrom;
pub mod peer;
pub mod protocol;
pub mod routing;
pub mod server;
pub mod session;
pub mod state;
pub mod transport;
pub mod utils;

