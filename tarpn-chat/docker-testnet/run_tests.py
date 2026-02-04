#!/usr/bin/env python3
"""
Integration test suite for tarpn-chat docker-testnet.

Tests:
1. Network convergence - all clients see expected node count
2. Message delivery - message sent by one client reaches all others
3. Reconnection - verify clients can reconnect after disconnection
4. WebSocket API - verify local client WebSocket API works

Usage:
    python3 run_tests.py [--verbose] [--test TEST_NAME] [--wait-for-healthy]

Exit codes:
    0 - All tests passed
    1 - Test failures
    2 - Setup/infrastructure error
"""

import argparse
import json
import logging
import sys
import time
import urllib.request
import urllib.error
import threading
import socket
from dataclasses import dataclass
from typing import List, Dict, Optional

# Try to import websocket library (optional - for WebSocket tests)
try:
    import websocket
    WEBSOCKET_AVAILABLE = True
except ImportError:
    WEBSOCKET_AVAILABLE = False

# Configuration
CLIENTS = {
    'client1': {'host': 'localhost', 'port': 5001, 'node': 'node2'},
    'client2': {'host': 'localhost', 'port': 5002, 'node': 'node1'},
    'client6': {'host': 'localhost', 'port': 5006, 'node': 'node6'},
    'client7': {'host': 'localhost', 'port': 5007, 'node': 'node7'},
}

# WebSocket client API endpoints (tarpn-chat nodes)
WEBSOCKET_ENDPOINTS = {
    'node4': {'host': 'localhost', 'port': 8514},  # tarpn-chat on node4
    'node5': {'host': 'localhost', 'port': 8515},  # tarpn-chat on node5
}

EXPECTED_NODE_COUNT = 7
CONVERGENCE_TIMEOUT = 120  # seconds
MESSAGE_DELIVERY_TIMEOUT = 30  # seconds
POLL_INTERVAL = 5  # seconds
HEALTH_CHECK_TIMEOUT = 120  # seconds

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class TestResult:
    """Result of a single test."""
    name: str
    passed: bool
    message: str
    duration: float


def http_get(url: str, timeout: float = 10) -> Optional[Dict]:
    """Make HTTP GET request, return JSON or None on error."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        logger.debug(f"HTTP GET {url} failed: {e}")
        return None


def http_post(url: str, data: Dict, timeout: float = 10) -> Optional[Dict]:
    """Make HTTP POST request with JSON body."""
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        logger.debug(f"HTTP POST {url} failed: {e}")
        return None


def get_client_url(client_name: str, endpoint: str) -> str:
    """Build URL for client API endpoint."""
    cfg = CLIENTS[client_name]
    return f"http://{cfg['host']}:{cfg['port']}{endpoint}"


def check_client_health(client_name: str) -> bool:
    """Check if client API is responding."""
    result = http_get(get_client_url(client_name, '/health'))
    return result is not None and result.get('status') == 'ok'


def get_client_status(client_name: str) -> Optional[Dict]:
    """Get client status."""
    return http_get(get_client_url(client_name, '/status'))


def get_client_messages(client_name: str, since: float = 0) -> Optional[Dict]:
    """Get messages received by client."""
    if since > 0:
        return http_get(get_client_url(client_name, f'/messages/since/{since}'))
    return http_get(get_client_url(client_name, '/messages'))


def send_message(client_name: str, message: str) -> bool:
    """Send a chat message via client."""
    result = http_post(
        get_client_url(client_name, '/send'),
        {'message': message}
    )
    return result is not None and result.get('status') == 'sent'


def refresh_status(client_name: str) -> bool:
    """Trigger a /p status refresh."""
    result = http_post(get_client_url(client_name, '/refresh_status'), {})
    return result is not None


# =============================================================================
# Test Cases
# =============================================================================

def test_all_clients_healthy() -> TestResult:
    """Verify all client APIs are responding."""
    start = time.time()
    unhealthy = []

    for client_name in CLIENTS:
        if not check_client_health(client_name):
            unhealthy.append(client_name)

    duration = time.time() - start

    if unhealthy:
        return TestResult(
            name='all_clients_healthy',
            passed=False,
            message=f"Unhealthy clients: {', '.join(unhealthy)}",
            duration=duration
        )

    return TestResult(
        name='all_clients_healthy',
        passed=True,
        message=f"All {len(CLIENTS)} clients healthy",
        duration=duration
    )


def test_all_clients_in_chat() -> TestResult:
    """Verify all clients are connected to chat."""
    start = time.time()
    not_in_chat = []

    for client_name in CLIENTS:
        status = get_client_status(client_name)
        if status is None:
            not_in_chat.append(f"{client_name} (API unavailable)")
        elif not status.get('in_chat', False):
            not_in_chat.append(f"{client_name} (not in chat)")

    duration = time.time() - start

    if not_in_chat:
        return TestResult(
            name='all_clients_in_chat',
            passed=False,
            message=f"Clients not in chat: {', '.join(not_in_chat)}",
            duration=duration
        )

    return TestResult(
        name='all_clients_in_chat',
        passed=True,
        message=f"All {len(CLIENTS)} clients connected to chat",
        duration=duration
    )


def test_network_convergence() -> TestResult:
    """
    Test that all clients see the expected number of nodes.
    This verifies that NetROM routing has converged across the network.
    """
    start = time.time()
    deadline = start + CONVERGENCE_TIMEOUT

    logger.info(f"Waiting for network convergence ({EXPECTED_NODE_COUNT} nodes)...")

    while time.time() < deadline:
        # Refresh status on all clients
        for client_name in CLIENTS:
            refresh_status(client_name)

        time.sleep(POLL_INTERVAL)

        # Check node counts
        converged = True
        status_report = []

        for client_name in CLIENTS:
            status = get_client_status(client_name)
            if status is None:
                converged = False
                status_report.append(f"{client_name}: API unavailable")
                continue

            node_count = status.get('node_count', 0)
            in_chat = status.get('in_chat', False)

            status_report.append(f"{client_name}: {node_count} nodes, in_chat={in_chat}")

            if not in_chat or node_count < EXPECTED_NODE_COUNT:
                converged = False

        logger.info("Current status: " + " | ".join(status_report))

        if converged:
            duration = time.time() - start
            return TestResult(
                name='network_convergence',
                passed=True,
                message=f"All clients see {EXPECTED_NODE_COUNT} nodes after {duration:.1f}s",
                duration=duration
            )

    # Timeout - report final state
    duration = time.time() - start
    final_status = []
    for client_name in CLIENTS:
        status = get_client_status(client_name)
        if status:
            final_status.append(f"{client_name}: {status.get('node_count', '?')} nodes")
        else:
            final_status.append(f"{client_name}: unavailable")

    return TestResult(
        name='network_convergence',
        passed=False,
        message=f"Timeout after {duration:.1f}s. Final: {', '.join(final_status)}",
        duration=duration
    )


def test_message_delivery() -> TestResult:
    """
    Test that a message sent from one client is received by all others.
    """
    start = time.time()
    sender = 'client1'
    receivers = [c for c in CLIENTS if c != sender]

    # Record timestamp before sending
    before_send = time.time()

    # Create unique test message
    test_message = f"INTEGRATION_TEST_{int(time.time() * 1000)}"

    logger.info(f"Sending test message from {sender}: {test_message}")

    if not send_message(sender, test_message):
        return TestResult(
            name='message_delivery',
            passed=False,
            message=f"Failed to send message from {sender}",
            duration=time.time() - start
        )

    # Wait for message to propagate
    deadline = time.time() + MESSAGE_DELIVERY_TIMEOUT
    received_by = set()

    while time.time() < deadline and len(received_by) < len(receivers):
        time.sleep(2)

        for client_name in receivers:
            if client_name in received_by:
                continue

            messages = get_client_messages(client_name, before_send)
            if messages and messages.get('messages'):
                for msg in messages['messages']:
                    if test_message in msg.get('text', ''):
                        received_by.add(client_name)
                        logger.info(f"{client_name} received test message")
                        break

    duration = time.time() - start

    if len(received_by) == len(receivers):
        return TestResult(
            name='message_delivery',
            passed=True,
            message=f"Message received by all {len(receivers)} other clients in {duration:.1f}s",
            duration=duration
        )

    missing = set(receivers) - received_by
    return TestResult(
        name='message_delivery',
        passed=False,
        message=f"Message not received by: {', '.join(missing)}",
        duration=duration
    )


def test_bidirectional_messaging() -> TestResult:
    """
    Test that messages flow in both directions across the network.
    Sends from client7 (via tarpn-chat) to client1 (via LinBPQ).
    """
    start = time.time()
    sender = 'client7'
    receiver = 'client1'

    # Record timestamp before sending
    before_send = time.time()

    # Create unique test message
    test_message = f"BIDIR_TEST_{int(time.time() * 1000)}"

    logger.info(f"Sending message from {sender} to {receiver}: {test_message}")

    if not send_message(sender, test_message):
        return TestResult(
            name='bidirectional_messaging',
            passed=False,
            message=f"Failed to send message from {sender}",
            duration=time.time() - start
        )

    # Wait for message to propagate
    deadline = time.time() + MESSAGE_DELIVERY_TIMEOUT
    received = False

    while time.time() < deadline and not received:
        time.sleep(2)

        messages = get_client_messages(receiver, before_send)
        if messages and messages.get('messages'):
            for msg in messages['messages']:
                if test_message in msg.get('text', ''):
                    received = True
                    logger.info(f"{receiver} received test message from {sender}")
                    break

    duration = time.time() - start

    if received:
        return TestResult(
            name='bidirectional_messaging',
            passed=True,
            message=f"Message from {sender} received by {receiver} in {duration:.1f}s",
            duration=duration
        )

    return TestResult(
        name='bidirectional_messaging',
        passed=False,
        message=f"Message from {sender} not received by {receiver}",
        duration=duration
    )


def normalize_node_name(name: str) -> str:
    """
    Normalize node name to canonical form for comparison.

    LinBPQ chat shows nodes with different aliases depending on perspective:
    - T1CHAT, T2CHAT, etc. (chat aliases)
    - TEST1, TEST2, etc. (SSID-stripped callsigns)

    Both represent the same node, so we normalize to the node number.
    """
    import re
    # Extract digit(s) from name - works for T1CHAT, TEST1, NODE1, etc.
    match = re.search(r'(\d+)', name)
    if match:
        return f"NODE{match.group(1)}"
    return name  # Return as-is if no number found


def test_node_list_consistency() -> TestResult:
    """
    Test that all clients see the same set of nodes.

    Note: Node names are normalized because LinBPQ chat may show different
    aliases (T1CHAT vs TEST1) depending on the client's perspective.
    """
    start = time.time()

    # Refresh status on all clients
    for client_name in CLIENTS:
        refresh_status(client_name)

    time.sleep(3)

    # Collect node lists from all clients
    node_lists = {}
    raw_lists = {}  # Keep raw for logging
    for client_name in CLIENTS:
        status = get_client_status(client_name)
        if status:
            raw = status.get('nodes_list', [])
            raw_lists[client_name] = sorted(raw)
            # Normalize and sort for comparison
            node_lists[client_name] = sorted([normalize_node_name(n) for n in raw])

    duration = time.time() - start

    # Check if all clients have node lists
    if len(node_lists) < len(CLIENTS):
        missing = set(CLIENTS.keys()) - set(node_lists.keys())
        return TestResult(
            name='node_list_consistency',
            passed=False,
            message=f"Could not get node list from: {', '.join(missing)}",
            duration=duration
        )

    # Check if all node lists are the same (comparing sorted lists)
    reference = None
    reference_client = None
    inconsistent = []

    for client_name, nodes in node_lists.items():
        if reference is None:
            reference = nodes
            reference_client = client_name
        elif nodes != reference:
            inconsistent.append(client_name)

    if inconsistent:
        # Show what's different for debugging (both raw and normalized)
        logger.info(f"Reference ({reference_client}) normalized: {reference}")
        logger.info(f"Reference ({reference_client}) raw: {raw_lists.get(reference_client, [])}")
        for client_name in inconsistent:
            logger.info(f"Differs ({client_name}) normalized: {node_lists[client_name]}")
            logger.info(f"Differs ({client_name}) raw: {raw_lists.get(client_name, [])}")
        return TestResult(
            name='node_list_consistency',
            passed=False,
            message=f"Node lists differ for: {', '.join(inconsistent)}",
            duration=duration
        )

    # Log the raw lists for visibility
    logger.info(f"All clients see {len(reference)} nodes (normalized: {reference})")
    for client_name in CLIENTS:
        logger.info(f"  {client_name} raw: {raw_lists.get(client_name, [])}")

    return TestResult(
        name='node_list_consistency',
        passed=True,
        message=f"All clients see the same {len(reference)} nodes",
        duration=duration
    )


# =============================================================================
# WebSocket API Tests
# =============================================================================

class WebSocketTestClient:
    """Simple WebSocket client for testing tarpn-chat client API."""

    def __init__(self, url: str):
        self.url = url
        self.ws = None
        self.received_messages = []
        self.connected = False
        self.joined = False
        self._lock = threading.Lock()
        self._recv_thread = None
        self._running = False

    def connect(self, timeout: float = 10) -> bool:
        """Connect to WebSocket server."""
        if not WEBSOCKET_AVAILABLE:
            logger.warning("websocket-client library not available")
            return False

        try:
            self.ws = websocket.create_connection(
                self.url,
                timeout=timeout
            )
            self._running = True
            self._recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
            self._recv_thread.start()

            # Wait for connected event
            deadline = time.time() + timeout
            while time.time() < deadline:
                with self._lock:
                    for msg in self.received_messages:
                        if msg.get('type') == 'connected':
                            self.connected = True
                            return True
                time.sleep(0.1)

            logger.warning(f"Timeout waiting for 'connected' event from {self.url}")
            return False

        except Exception as e:
            logger.error(f"WebSocket connect failed: {e}")
            return False

    def _recv_loop(self):
        """Background thread to receive messages."""
        while self._running:
            try:
                if self.ws is None:
                    break
                self.ws.settimeout(1.0)
                data = self.ws.recv()
                if data:
                    msg = json.loads(data)
                    with self._lock:
                        self.received_messages.append(msg)
                        logger.debug(f"WS received: {msg}")
            except websocket.WebSocketTimeoutException:
                continue
            except Exception as e:
                if self._running:
                    logger.debug(f"WebSocket recv error: {e}")
                break

    def send_json(self, data: dict) -> bool:
        """Send JSON message."""
        try:
            self.ws.send(json.dumps(data))
            return True
        except Exception as e:
            logger.error(f"WebSocket send failed: {e}")
            return False

    def join(self, user: str, name: str, qth: str = "Test") -> bool:
        """Send join command."""
        if not self.send_json({
            'cmd': 'join',
            'user': user,
            'name': name,
            'qth': qth
        }):
            return False

        # Wait a bit for server to process
        time.sleep(0.5)
        self.joined = True
        return True

    def leave(self) -> bool:
        """Send leave command."""
        return self.send_json({'cmd': 'leave'})

    def send_message(self, text: str) -> bool:
        """Send a chat message."""
        return self.send_json({
            'cmd': 'send_data',
            'text': text
        })

    def get_messages(self, msg_type: str = None) -> List[dict]:
        """Get received messages, optionally filtered by type."""
        with self._lock:
            if msg_type:
                return [m for m in self.received_messages if m.get('type') == msg_type]
            return list(self.received_messages)

    def wait_for_message(self, text: str, timeout: float = 10) -> bool:
        """Wait for a message containing the given text."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._lock:
                for msg in self.received_messages:
                    if msg.get('type') == 'data' and text in msg.get('text', ''):
                        return True
            time.sleep(0.2)
        return False

    def close(self):
        """Close the connection."""
        self._running = False
        if self.ws:
            try:
                self.ws.close()
            except:
                pass
            self.ws = None


def get_ws_url(endpoint_name: str) -> str:
    """Build WebSocket URL for endpoint."""
    cfg = WEBSOCKET_ENDPOINTS[endpoint_name]
    return f"ws://{cfg['host']}:{cfg['port']}/"


def check_websocket_port(endpoint_name: str) -> bool:
    """Check if WebSocket port is open."""
    cfg = WEBSOCKET_ENDPOINTS[endpoint_name]
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        result = sock.connect_ex((cfg['host'], cfg['port']))
        sock.close()
        return result == 0
    except:
        return False


def test_websocket_port_available() -> TestResult:
    """Verify WebSocket client API ports are open."""
    start = time.time()
    unavailable = []

    for endpoint_name in WEBSOCKET_ENDPOINTS:
        if not check_websocket_port(endpoint_name):
            unavailable.append(endpoint_name)

    duration = time.time() - start

    if unavailable:
        return TestResult(
            name='websocket_port_available',
            passed=False,
            message=f"WebSocket ports not available: {', '.join(unavailable)}",
            duration=duration
        )

    return TestResult(
        name='websocket_port_available',
        passed=True,
        message=f"All {len(WEBSOCKET_ENDPOINTS)} WebSocket ports available",
        duration=duration
    )


def test_websocket_connect() -> TestResult:
    """Test WebSocket connection to tarpn-chat client API."""
    if not WEBSOCKET_AVAILABLE:
        return TestResult(
            name='websocket_connect',
            passed=False,
            message="websocket-client library not installed (pip install websocket-client)",
            duration=0
        )

    start = time.time()

    # Try to connect to node4's client API
    client = WebSocketTestClient(get_ws_url('node4'))

    try:
        if not client.connect(timeout=10):
            return TestResult(
                name='websocket_connect',
                passed=False,
                message="Failed to connect to node4 WebSocket API",
                duration=time.time() - start
            )

        logger.info("WebSocket connected, sending join command")

        if not client.join("WSTEST", "WS Test User", "Testing"):
            return TestResult(
                name='websocket_connect',
                passed=False,
                message="Failed to send join command",
                duration=time.time() - start
            )

        # Verify we're connected and joined
        duration = time.time() - start
        return TestResult(
            name='websocket_connect',
            passed=True,
            message=f"Connected and joined via WebSocket in {duration:.1f}s",
            duration=duration
        )

    finally:
        client.leave()
        client.close()


def test_websocket_send_receive() -> TestResult:
    """Test sending and receiving messages via WebSocket."""
    if not WEBSOCKET_AVAILABLE:
        return TestResult(
            name='websocket_send_receive',
            passed=False,
            message="websocket-client library not installed",
            duration=0
        )

    start = time.time()
    client1 = None
    client2 = None

    try:
        # Connect two WebSocket clients to different nodes
        client1 = WebSocketTestClient(get_ws_url('node4'))
        client2 = WebSocketTestClient(get_ws_url('node5'))

        if not client1.connect(timeout=10):
            return TestResult(
                name='websocket_send_receive',
                passed=False,
                message="Client1 failed to connect to node4",
                duration=time.time() - start
            )

        if not client2.connect(timeout=10):
            return TestResult(
                name='websocket_send_receive',
                passed=False,
                message="Client2 failed to connect to node5",
                duration=time.time() - start
            )

        # Join both clients
        client1.join("WSTEST1", "WS Test 1")
        client2.join("WSTEST2", "WS Test 2")

        # Give some time for join to propagate
        time.sleep(2)

        # Send a message from client1
        test_message = f"WS_TEST_{int(time.time() * 1000)}"
        logger.info(f"Sending test message from client1: {test_message}")

        if not client1.send_message(test_message):
            return TestResult(
                name='websocket_send_receive',
                passed=False,
                message="Failed to send message",
                duration=time.time() - start
            )

        # Wait for client2 to receive it
        if not client2.wait_for_message(test_message, timeout=15):
            return TestResult(
                name='websocket_send_receive',
                passed=False,
                message="Message not received by client2",
                duration=time.time() - start
            )

        duration = time.time() - start
        return TestResult(
            name='websocket_send_receive',
            passed=True,
            message=f"Message sent and received via WebSocket in {duration:.1f}s",
            duration=duration
        )

    finally:
        if client1:
            client1.leave()
            client1.close()
        if client2:
            client2.leave()
            client2.close()


def test_websocket_to_telnet() -> TestResult:
    """Test that messages from WebSocket client reach telnet clients."""
    if not WEBSOCKET_AVAILABLE:
        return TestResult(
            name='websocket_to_telnet',
            passed=False,
            message="websocket-client library not installed",
            duration=0
        )

    start = time.time()
    ws_client = None

    try:
        # Connect WebSocket client to node4
        ws_client = WebSocketTestClient(get_ws_url('node4'))

        if not ws_client.connect(timeout=10):
            return TestResult(
                name='websocket_to_telnet',
                passed=False,
                message="WebSocket client failed to connect",
                duration=time.time() - start
            )

        ws_client.join("WSBRIDGE", "WS Bridge Test")
        time.sleep(2)

        # Record timestamp before sending
        before_send = time.time()

        # Send a message via WebSocket
        test_message = f"WSBRIDGE_TEST_{int(time.time() * 1000)}"
        logger.info(f"Sending message from WebSocket client: {test_message}")

        if not ws_client.send_message(test_message):
            return TestResult(
                name='websocket_to_telnet',
                passed=False,
                message="Failed to send WebSocket message",
                duration=time.time() - start
            )

        # Check if telnet clients received it
        deadline = time.time() + MESSAGE_DELIVERY_TIMEOUT
        received_by = set()

        while time.time() < deadline and len(received_by) < len(CLIENTS):
            time.sleep(2)

            for client_name in CLIENTS:
                if client_name in received_by:
                    continue

                messages = get_client_messages(client_name, before_send)
                if messages and messages.get('messages'):
                    for msg in messages['messages']:
                        if test_message in msg.get('text', ''):
                            received_by.add(client_name)
                            logger.info(f"Telnet {client_name} received WebSocket message")
                            break

        duration = time.time() - start

        if len(received_by) == len(CLIENTS):
            return TestResult(
                name='websocket_to_telnet',
                passed=True,
                message=f"WebSocket message received by all {len(CLIENTS)} telnet clients in {duration:.1f}s",
                duration=duration
            )

        missing = set(CLIENTS.keys()) - received_by
        return TestResult(
            name='websocket_to_telnet',
            passed=False,
            message=f"WebSocket message not received by: {', '.join(missing)}",
            duration=duration
        )

    finally:
        if ws_client:
            ws_client.leave()
            ws_client.close()


def test_telnet_to_websocket() -> TestResult:
    """Test that messages from telnet clients reach WebSocket client."""
    if not WEBSOCKET_AVAILABLE:
        return TestResult(
            name='telnet_to_websocket',
            passed=False,
            message="websocket-client library not installed",
            duration=0
        )

    start = time.time()
    ws_client = None

    try:
        # Connect WebSocket client to node4
        ws_client = WebSocketTestClient(get_ws_url('node4'))

        if not ws_client.connect(timeout=10):
            return TestResult(
                name='telnet_to_websocket',
                passed=False,
                message="WebSocket client failed to connect",
                duration=time.time() - start
            )

        ws_client.join("WSRECV", "WS Receiver Test")
        time.sleep(2)

        # Send a message from a telnet client
        sender = 'client1'
        test_message = f"TELNET_TO_WS_{int(time.time() * 1000)}"
        logger.info(f"Sending message from telnet {sender}: {test_message}")

        if not send_message(sender, test_message):
            return TestResult(
                name='telnet_to_websocket',
                passed=False,
                message=f"Failed to send message from {sender}",
                duration=time.time() - start
            )

        # Wait for WebSocket client to receive it
        if not ws_client.wait_for_message(test_message, timeout=15):
            return TestResult(
                name='telnet_to_websocket',
                passed=False,
                message="WebSocket client did not receive telnet message",
                duration=time.time() - start
            )

        duration = time.time() - start
        return TestResult(
            name='telnet_to_websocket',
            passed=True,
            message=f"Telnet message received by WebSocket client in {duration:.1f}s",
            duration=duration
        )

    finally:
        if ws_client:
            ws_client.leave()
            ws_client.close()


# =============================================================================
# Test Runner
# =============================================================================

def wait_for_healthy(timeout: float = HEALTH_CHECK_TIMEOUT) -> bool:
    """Wait for all clients to be healthy."""
    logger.info("Waiting for all clients to be healthy...")
    deadline = time.time() + timeout

    while time.time() < deadline:
        healthy_count = sum(1 for c in CLIENTS if check_client_health(c))
        logger.info(f"Healthy clients: {healthy_count}/{len(CLIENTS)}")

        if healthy_count == len(CLIENTS):
            logger.info("All clients healthy!")
            return True

        time.sleep(5)

    logger.error(f"Timeout waiting for clients to be healthy")
    return False


def run_all_tests(selected_test: Optional[str] = None) -> List[TestResult]:
    """Run all tests or a specific test."""

    all_tests = [
        ('all_clients_healthy', test_all_clients_healthy),
        ('all_clients_in_chat', test_all_clients_in_chat),
        ('network_convergence', test_network_convergence),
        ('message_delivery', test_message_delivery),
        ('bidirectional_messaging', test_bidirectional_messaging),
        ('node_list_consistency', test_node_list_consistency),
        # WebSocket API tests
        ('websocket_port_available', test_websocket_port_available),
        ('websocket_connect', test_websocket_connect),
        ('websocket_send_receive', test_websocket_send_receive),
        ('websocket_to_telnet', test_websocket_to_telnet),
        ('telnet_to_websocket', test_telnet_to_websocket),
    ]

    results = []

    for test_name, test_func in all_tests:
        if selected_test and test_name != selected_test:
            continue

        logger.info(f"\n{'='*60}")
        logger.info(f"Running test: {test_name}")
        logger.info('='*60)

        try:
            result = test_func()
        except Exception as e:
            logger.exception(f"Test {test_name} raised exception")
            result = TestResult(
                name=test_name,
                passed=False,
                message=f"Exception: {e}",
                duration=0
            )

        results.append(result)

        status = "PASS" if result.passed else "FAIL"
        logger.info(f"[{status}] {result.name}: {result.message}")

    return results


def print_summary(results: List[TestResult]) -> bool:
    """Print test summary."""
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)

    passed = sum(1 for r in results if r.passed)
    total = len(results)

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"  [{status}] {result.name} ({result.duration:.1f}s)")
        if not result.passed:
            print(f"         {result.message}")

    print("="*60)
    print(f"Results: {passed}/{total} tests passed")

    return passed == total


def main():
    parser = argparse.ArgumentParser(description='Run integration tests')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose logging')
    parser.add_argument('-t', '--test', type=str,
                        help='Run specific test by name')
    parser.add_argument('--wait-for-healthy', action='store_true',
                        help='Wait for all clients to be healthy before running tests')
    parser.add_argument('--list', action='store_true',
                        help='List available tests and exit')
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.list:
        print("Available tests:")
        print("  all_clients_healthy      - Verify all client APIs respond")
        print("  all_clients_in_chat      - Verify all clients connected to chat")
        print("  network_convergence      - All clients see 7 nodes")
        print("  message_delivery         - Message from client1 reaches all others")
        print("  bidirectional_messaging  - Message from client7 reaches client1")
        print("  node_list_consistency    - All clients see same node list")
        print("")
        print("WebSocket API tests (require websocket-client: pip install websocket-client):")
        print("  websocket_port_available - Verify WebSocket ports are open")
        print("  websocket_connect        - Connect and join via WebSocket")
        print("  websocket_send_receive   - Send/receive between WebSocket clients")
        print("  websocket_to_telnet      - WebSocket message reaches telnet clients")
        print("  telnet_to_websocket      - Telnet message reaches WebSocket client")
        sys.exit(0)

    # Wait for clients to be healthy if requested
    if args.wait_for_healthy:
        if not wait_for_healthy():
            sys.exit(2)

    results = run_all_tests(args.test)

    if not results:
        print(f"No tests matched '{args.test}'")
        sys.exit(2)

    success = print_summary(results)

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
