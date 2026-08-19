//! State management for nodes, circuits, and routing
//!
//! Key concepts:
//! - Node: A chat server instance in the network
//! - Circuit: An active connection (to a linked node)
//! - Each circuit tracks which nodes are reachable through it (for loop prevention)
//!
//! Note: Much of this infrastructure is scaffolding for future features
//! (message routing, circuit management, duplicate detection).

#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;

use crate::utils::strip_ssid;

/// Unique identifier for a circuit
pub type CircuitId = u64;

/// Represents a user connected to the network
#[derive(Debug, Clone)]
pub struct User {
    /// User callsign
    pub call: String,

    /// Node the user is connected to
    pub node_call: String,

    /// User's name
    pub name: String,

    /// User's location
    pub qth: String,

    /// Current topic
    pub topic: String,

    /// Circuit through which this user is reachable
    pub circuit_id: CircuitId,
}

impl User {
    pub fn new(call: String, node_call: String, name: String, qth: String, circuit_id: CircuitId) -> Self {
        Self {
            call,
            node_call,
            name,
            qth,
            topic: "General".to_string(),
            circuit_id,
        }
    }

    /// Unique key for this user (user@node)
    pub fn key(&self) -> String {
        format!("{}@{}", self.call, self.node_call)
    }
}

/// Represents a known node in the network
#[derive(Debug, Clone)]
pub struct Node {
    /// Node callsign
    pub call: String,

    /// Node alias
    pub alias: String,

    /// Node version (if known)
    pub version: Option<String>,

    /// Circuits through which this node is reachable
    /// Maps circuit_id -> reference count (node may be reachable via multiple paths)
    pub circuits: HashMap<CircuitId, u32>,

    /// When this node was first seen
    pub first_seen: Instant,
}

impl Node {
    pub fn new(call: String, alias: String, version: Option<String>) -> Self {
        Self {
            call,
            alias,
            version,
            circuits: HashMap::new(),
            first_seen: Instant::now(),
        }
    }

    /// Check if this node is reachable via a specific circuit
    pub fn is_reachable_via(&self, circuit_id: CircuitId) -> bool {
        self.circuits.contains_key(&circuit_id)
    }

    /// Add a circuit path to this node
    pub fn add_circuit(&mut self, circuit_id: CircuitId) {
        *self.circuits.entry(circuit_id).or_insert(0) += 1;
    }

    /// Remove a circuit path from this node
    /// Returns true if node has no more reachable paths
    pub fn remove_circuit(&mut self, circuit_id: CircuitId) -> bool {
        if let Some(count) = self.circuits.get_mut(&circuit_id) {
            *count -= 1;
            if *count == 0 {
                self.circuits.remove(&circuit_id);
            }
        }
        self.circuits.is_empty()
    }
}

/// State of a circuit connection
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CircuitState {
    /// Connection in progress
    Connecting,
    /// Waiting for handshake completion
    Handshaking,
    /// Fully connected and operational
    Connected,
    /// Disconnecting
    Disconnecting,
}

/// Represents an active connection to a linked node
#[derive(Debug)]
pub struct Circuit {
    /// Unique identifier
    pub id: CircuitId,

    /// Connected node callsign
    pub node_call: String,

    /// Connection state
    pub state: CircuitState,

    /// Nodes reachable through this circuit
    pub reachable_nodes: HashSet<String>,

    /// When last data was received
    pub last_received: Instant,

    /// When a poll was sent (if any)
    pub poll_sent: Option<Instant>,

    /// Whether this is an outgoing connection (we initiated)
    pub is_outgoing: bool,

    /// When the circuit was established
    pub connected_at: Instant,
}

impl Circuit {
    pub fn new(id: CircuitId, node_call: String, is_outgoing: bool) -> Self {
        let now = Instant::now();
        Self {
            id,
            node_call,
            state: CircuitState::Connecting,
            reachable_nodes: HashSet::new(),
            last_received: now,
            poll_sent: None,
            is_outgoing,
            connected_at: now,
        }
    }

    /// Mark that we received data on this circuit
    pub fn touch(&mut self) {
        self.last_received = Instant::now();
        self.poll_sent = None; // Clear pending poll
    }

    /// Check if circuit has been idle too long
    pub fn is_idle(&self, timeout_secs: u64) -> bool {
        self.last_received.elapsed().as_secs() > timeout_secs
    }

    /// Check if poll response is overdue
    pub fn is_poll_timeout(&self, timeout_secs: u64) -> bool {
        self.poll_sent
            .map(|t| t.elapsed().as_secs() > timeout_secs)
            .unwrap_or(false)
    }
}

/// Duplicate detection entry
#[derive(Debug)]
struct DupEntry {
    time: Instant,
    user: String,
    text: String,
}

/// Duplicate detection cache
#[derive(Debug)]
pub struct DupCache {
    entries: Vec<DupEntry>,
    max_entries: usize,
    window_secs: u64,
}

impl DupCache {
    pub fn new(max_entries: usize, window_secs: u64) -> Self {
        Self {
            entries: Vec::with_capacity(max_entries),
            max_entries,
            window_secs,
        }
    }

    /// Check if message is a duplicate
    pub fn is_duplicate(&self, user: &str, text: &str) -> bool {
        let user_prefix: String = user.chars().take(10).collect();
        let text_prefix: String = text.chars().take(100).collect();

        self.entries.iter().any(|e| {
            e.time.elapsed().as_secs() < self.window_secs
                && e.user == user_prefix
                && e.text == text_prefix
        })
    }

    /// Add message to cache
    pub fn add(&mut self, user: &str, text: &str) {
        // Prune old entries
        let now = Instant::now();
        self.entries
            .retain(|e| e.time.elapsed().as_secs() < self.window_secs);

        // Add new entry (circular buffer behavior)
        if self.entries.len() >= self.max_entries {
            self.entries.remove(0);
        }

        self.entries.push(DupEntry {
            time: now,
            user: user.chars().take(10).collect(),
            text: text.chars().take(100).collect(),
        });
    }
}

impl Default for DupCache {
    fn default() -> Self {
        Self::new(10, 5)
    }
}

/// Central state for the chat server
pub struct ServerState {
    /// Our node callsign
    pub our_call: String,

    /// Our node alias
    pub our_alias: String,

    /// All known nodes in the network
    pub nodes: HashMap<String, Node>,

    /// Active circuits
    pub circuits: HashMap<CircuitId, Circuit>,

    /// Connected users (keyed by "user@node")
    pub users: HashMap<String, User>,

    /// Next circuit ID
    next_circuit_id: CircuitId,

    /// Duplicate detection cache
    pub dup_cache: DupCache,
}

impl ServerState {
    pub fn new(our_call: String, our_alias: String) -> Self {
        let mut state = Self {
            our_call: our_call.clone(),
            our_alias: our_alias.clone(),
            nodes: HashMap::new(),
            circuits: HashMap::new(),
            users: HashMap::new(),
            next_circuit_id: 1,
            dup_cache: DupCache::default(),
        };

        // Add ourselves as a known node
        state.nodes.insert(
            our_call.clone(),
            Node::new(our_call, our_alias, Some(crate::protocol::VERSION.into())),
        );

        state
    }

    /// Allocate a new circuit ID
    pub fn next_circuit_id(&mut self) -> CircuitId {
        let id = self.next_circuit_id;
        self.next_circuit_id += 1;
        id
    }

    /// Register a new circuit
    pub fn add_circuit(&mut self, circuit: Circuit) {
        self.circuits.insert(circuit.id, circuit);
    }

    /// Remove a circuit and clean up node references
    pub fn remove_circuit(&mut self, circuit_id: CircuitId) -> Option<Circuit> {
        if let Some(circuit) = self.circuits.remove(&circuit_id) {
            // Remove this circuit from all nodes' reachability
            let nodes_to_check: Vec<String> = circuit.reachable_nodes.iter().cloned().collect();
            for node_call in nodes_to_check {
                if let Some(node) = self.nodes.get_mut(&node_call) {
                    let unreachable = node.remove_circuit(circuit_id);
                    // Don't remove ourselves or nodes reachable via other circuits
                    if unreachable && node_call != self.our_call {
                        self.nodes.remove(&node_call);
                    }
                }
            }
            Some(circuit)
        } else {
            None
        }
    }

    /// Register that a node is reachable via a circuit
    pub fn add_node_route(&mut self, circuit_id: CircuitId, node_call: &str, alias: &str, version: Option<String>) {
        // Add or update node
        let node = self.nodes.entry(node_call.to_string()).or_insert_with(|| {
            Node::new(node_call.into(), alias.into(), version.clone())
        });
        node.add_circuit(circuit_id);

        // Update alias if we received a better one (non-empty replaces empty,
        // or proper chat alias replaces SSID-stripped callsign)
        if !alias.is_empty() && (node.alias.is_empty() || node.alias == strip_ssid(node_call)) {
            node.alias = alias.to_string();
        }

        if version.is_some() {
            node.version = version;
        }

        // Track in circuit
        if let Some(circuit) = self.circuits.get_mut(&circuit_id) {
            circuit.reachable_nodes.insert(node_call.to_string());
        }
    }

    /// Check if a node is reachable via a specific circuit (for loop prevention)
    pub fn is_node_reachable_via(&self, node_call: &str, circuit_id: CircuitId) -> bool {
        self.nodes
            .get(node_call)
            .map(|n| n.is_reachable_via(circuit_id))
            .unwrap_or(false)
    }

    /// Get circuit IDs to forward a message to (excluding source and loops)
    pub fn get_forward_circuits(&self, source_node: &str, from_circuit: CircuitId) -> Vec<CircuitId> {
        self.circuits
            .iter()
            .filter(|(id, circuit)| {
                // Skip source circuit
                **id != from_circuit
                    // Skip if source node is reachable via this circuit (loop prevention)
                    && !circuit.reachable_nodes.contains(source_node)
                    // Only forward to connected circuits
                    && circuit.state == CircuitState::Connected
            })
            .map(|(id, _)| *id)
            .collect()
    }

    /// Check if we know about a node
    pub fn has_node(&self, call: &str) -> bool {
        self.nodes.contains_key(call)
    }

    /// Check if a peer is connected (has an active circuit)
    pub fn is_peer_connected(&self, peer_call: &str) -> bool {
        self.circuits
            .values()
            .any(|c| c.node_call == peer_call && c.state == CircuitState::Connected)
    }

    /// Add or update a user
    pub fn add_user(&mut self, call: &str, node_call: &str, name: &str, qth: &str, circuit_id: CircuitId) {
        let key = format!("{}@{}", call, node_call);
        let user = self.users.entry(key).or_insert_with(|| {
            User::new(call.into(), node_call.into(), name.into(), qth.into(), circuit_id)
        });
        user.name = name.into();
        user.qth = qth.into();
        user.circuit_id = circuit_id;
    }

    /// Update a user's topic
    pub fn set_user_topic(&mut self, call: &str, node_call: &str, topic: &str) {
        let key = format!("{}@{}", call, node_call);
        if let Some(user) = self.users.get_mut(&key) {
            user.topic = topic.into();
        }
    }

    /// Apply a user's name/QTH update.
    ///
    /// Only ever an update: Join is what introduces a user, and an Info for
    /// someone we have not seen is either out of order or from a node whose
    /// Join we missed. Inserting on it would create a user with no circuit,
    /// which nothing would then clean up when their node goes away.
    pub fn set_user_info(&mut self, call: &str, node_call: &str, name: &str, qth: &str) -> bool {
        let key = format!("{}@{}", call, node_call);
        match self.users.get_mut(&key) {
            Some(user) => {
                user.name = name.into();
                user.qth = qth.into();
                true
            }
            None => false,
        }
    }

    /// Remove a user
    pub fn remove_user(&mut self, call: &str, node_call: &str) {
        let key = format!("{}@{}", call, node_call);
        self.users.remove(&key);
    }

    /// Remove all users on a circuit
    pub fn remove_users_on_circuit(&mut self, circuit_id: CircuitId) {
        self.users.retain(|_, user| user.circuit_id != circuit_id);
    }

    /// Get all users on a specific node (by node callsign)
    pub fn get_users_on_node(&self, node_call: &str) -> Vec<User> {
        self.users
            .values()
            .filter(|u| u.node_call == node_call)
            .cloned()
            .collect()
    }

    /// Remove all users on a specific node, returning the removed users
    pub fn remove_users_on_node(&mut self, node_call: &str) -> Vec<User> {
        let removed: Vec<User> = self.users
            .values()
            .filter(|u| u.node_call == node_call)
            .cloned()
            .collect();
        self.users.retain(|_, user| user.node_call != node_call);
        removed
    }

    /// Get all users NOT on a specific circuit (for announcing to new peers)
    pub fn get_users_not_on_circuit(&self, circuit_id: CircuitId) -> Vec<User> {
        self.users
            .values()
            .filter(|u| u.circuit_id != circuit_id)
            .cloned()
            .collect()
    }

    /// Get a circuit by ID
    pub fn get_circuit(&self, id: CircuitId) -> Option<&Circuit> {
        self.circuits.get(&id)
    }

    /// Get a mutable circuit by ID
    pub fn get_circuit_mut(&mut self, id: CircuitId) -> Option<&mut Circuit> {
        self.circuits.get_mut(&id)
    }
}

/// Thread-safe wrapper for server state
pub type SharedState = Arc<RwLock<ServerState>>;

/// Create a new shared state
pub fn new_shared_state(our_call: String, our_alias: String) -> SharedState {
    Arc::new(RwLock::new(ServerState::new(our_call, our_alias)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dup_cache() {
        let mut cache = DupCache::new(3, 5);

        assert!(!cache.is_duplicate("N0CALL", "hello"));
        cache.add("N0CALL", "hello");
        assert!(cache.is_duplicate("N0CALL", "hello"));
        assert!(!cache.is_duplicate("N0CALL", "world"));
    }

    #[test]
    fn test_node_reachability() {
        let mut state = ServerState::new("WA2M-9".into(), "BOT".into());

        let circuit_id = state.next_circuit_id();
        let circuit = Circuit::new(circuit_id, "KB1ABC".into(), true);
        state.add_circuit(circuit);

        state.add_node_route(circuit_id, "KB1ABC", "RDGCHT", None);
        state.add_node_route(circuit_id, "N0XYZ", "REMOTE", None);

        assert!(state.is_node_reachable_via("KB1ABC", circuit_id));
        assert!(state.is_node_reachable_via("N0XYZ", circuit_id));
        assert!(!state.is_node_reachable_via("UNKNOWN", circuit_id));
    }

    #[test]
    fn test_forward_circuits() {
        let mut state = ServerState::new("WA2M-9".into(), "BOT".into());

        // Create two circuits
        let c1_id = state.next_circuit_id();
        let mut c1 = Circuit::new(c1_id, "KB1ABC".into(), true);
        c1.state = CircuitState::Connected;
        state.add_circuit(c1);
        state.add_node_route(c1_id, "KB1ABC", "RDGCHT", None);

        let c2_id = state.next_circuit_id();
        let mut c2 = Circuit::new(c2_id, "N0XYZ".into(), false);
        c2.state = CircuitState::Connected;
        state.add_circuit(c2);
        state.add_node_route(c2_id, "N0XYZ", "REMOTE", None);

        // Message from KB1ABC should forward to c2 only
        let forward = state.get_forward_circuits("KB1ABC", c1_id);
        assert_eq!(forward.len(), 1);
        assert!(forward.contains(&c2_id));

        // Message from N0XYZ should forward to c1 only
        let forward = state.get_forward_circuits("N0XYZ", c2_id);
        assert_eq!(forward.len(), 1);
        assert!(forward.contains(&c1_id));
    }
}

#[cfg(test)]
mod user_info_tests {
    use super::*;

    // A user's name and QTH must be updatable after they join. Both halves of
    // this were broken: SetInfo updated only the local client record, so a peer
    // connecting later was announced the join-time values out of this table,
    // and an incoming Info was logged and discarded, so peers already connected
    // never applied a change either. The result was that an operator editing
    // their details saw the new ones locally while everyone else kept the old.
    #[test]
    fn set_user_info_updates_an_existing_user() {
        let mut st = ServerState::new("WA2M-9".into(), "ZA2M09".into());
        st.add_user("WA2M", "WA2M-9", "Mike", "Raleigh", 1);

        assert!(st.set_user_info("WA2M", "WA2M-9", "Mike K", "Durham"));

        let u = st.users.get("WA2M@WA2M-9").expect("user still present");
        assert_eq!(u.name, "Mike K");
        assert_eq!(u.qth, "Durham");
    }

    // Only ever an update. Join introduces a user; inserting here would create
    // one with no circuit, which nothing cleans up when their node goes away.
    #[test]
    fn set_user_info_ignores_an_unknown_user() {
        let mut st = ServerState::new("WA2M-9".into(), "ZA2M09".into());
        assert!(!st.set_user_info("NOBODY", "N0CALL-9", "Ghost", "Nowhere"));
        assert!(st.users.is_empty());
    }

    // The topic is kept separately and must survive an info update.
    #[test]
    fn set_user_info_leaves_the_topic_alone() {
        let mut st = ServerState::new("WA2M-9".into(), "ZA2M09".into());
        st.add_user("WA2M", "WA2M-9", "Mike", "Raleigh", 1);
        st.set_user_topic("WA2M", "WA2M-9", "testing");

        st.set_user_info("WA2M", "WA2M-9", "Mike K", "Durham");

        let u = st.users.get("WA2M@WA2M-9").unwrap();
        assert_eq!(u.topic, "testing");
        assert_eq!(u.name, "Mike K");
    }
}
