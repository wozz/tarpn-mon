#!/usr/bin/env python3
"""
Persistent chat client for LinBPQ chat testing.
Stays connected to chat, logs events, and keeps links alive.
Exposes HTTP API for test queries.
"""

import socket
import time
import os
import sys
import logging
import random
import re
import json
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

# Configuration from environment
HOST = os.environ.get('CHAT_HOST', 'localhost')
PORT = int(os.environ.get('CHAT_PORT', '8010'))
CALLSIGN = os.environ.get('CHAT_CALLSIGN', 'TESTUSER')
PASSWORD = os.environ.get('CHAT_PASSWORD', 'test')
USERNAME = os.environ.get('CHAT_USERNAME', 'TestUser')
RECONNECT_DELAY = int(os.environ.get('RECONNECT_DELAY', '10'))
# Message sending config
SEND_MESSAGES = os.environ.get('SEND_MESSAGES', 'true').lower() == 'true'
MESSAGE_INTERVAL = int(os.environ.get('MESSAGE_INTERVAL', '60'))  # Base interval in seconds
MESSAGE_JITTER = int(os.environ.get('MESSAGE_JITTER', '15'))  # Random jitter in seconds
CLIENT_ID = os.environ.get('CLIENT_ID', CALLSIGN)  # Unique ID for this client
# HTTP API config
HTTP_PORT = int(os.environ.get('HTTP_PORT', '5000'))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)


class ChatClient:
    def __init__(self, host, port, callsign, password, username):
        self.host = host
        self.port = port
        self.callsign = callsign
        self.password = password
        self.username = username
        self.sock = None
        self.connected = False
        self.in_chat = False

        # State tracking for HTTP API
        self.state_lock = threading.Lock()
        self.messages_received = []       # List of {timestamp, from_user, from_node, text}
        self.messages_sent = 0
        self.messages_received_count = 0
        self.node_count = 0
        self.user_list = []               # List of {user, node, name}
        self.nodes_list = []              # List of node names
        self.connection_history = []      # List of {timestamp, event, details}
        self.last_status_response = None
        self.status_refresh_requested = False
        self.pending_message = None       # Message to send via API

    def _record_event(self, event, details=""):
        """Record a connection event."""
        with self.state_lock:
            self.connection_history.append({
                'timestamp': time.time(),
                'iso_time': datetime.utcnow().isoformat() + 'Z',
                'event': event,
                'details': details
            })
            # Keep only last 50 events
            if len(self.connection_history) > 50:
                self.connection_history = self.connection_history[-50:]

    def connect(self):
        """Establish connection to LinBPQ telnet server."""
        try:
            logger.info(f"Connecting to {self.host}:{self.port}...")
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(30)
            self.sock.connect((self.host, self.port))
            self.connected = True
            self._record_event('connected', f"{self.host}:{self.port}")
            logger.info("TCP connection established")
            return True
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            self.connected = False
            self._record_event('connect_failed', str(e))
            return False

    def disconnect(self):
        """Close connection."""
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
        self.sock = None
        was_connected = self.connected
        self.connected = False
        self.in_chat = False
        if was_connected:
            self._record_event('disconnected')

    def send(self, data):
        """Send data to server."""
        if not self.connected:
            return False
        try:
            if isinstance(data, str):
                data = data.encode('latin-1')
            self.sock.send(data)
            return True
        except Exception as e:
            logger.error(f"Send failed: {e}")
            self.connected = False
            return False

    def recv_all(self, timeout=5.0):
        """Receive all available data with timeout."""
        if not self.connected:
            return None
        try:
            self.sock.settimeout(timeout)
            data = self.sock.recv(4096)
            if not data:
                logger.warning("Connection closed by server")
                self.connected = False
                return None
            return data
        except socket.timeout:
            return b''
        except Exception as e:
            logger.error(f"Recv failed: {e}")
            self.connected = False
            return None

    def wait_and_collect(self, timeout=5.0):
        """Collect data over a period, handling multiple chunks."""
        buffer = b''
        end_time = time.time() + timeout
        while time.time() < end_time:
            remaining = end_time - time.time()
            if remaining <= 0:
                break
            data = self.recv_all(min(remaining, 0.5))
            if data is None:
                return None
            if data:
                buffer += data
        return buffer

    def login_and_enter_chat(self):
        """Complete login and enter chat in one sequence."""
        # Wait for initial telnet negotiation + callsign prompt
        logger.info("Waiting for login prompt...")
        initial = self.wait_and_collect(3.0)
        if initial:
            text = initial.decode('latin-1', errors='replace')
            logger.info(f"Initial prompt received ({len(initial)} bytes)")
            # Check if Callsign prompt is there
            if "Callsign:" not in text:
                logger.warning(f"Expected Callsign prompt, got: {repr(text[:50])}")

        # Send callsign
        logger.info(f"Sending callsign: {self.callsign}")
        self.send(f"{self.callsign}\r")

        # Wait for password prompt
        response = self.wait_and_collect(3.0)
        if response:
            text = response.decode('latin-1', errors='replace')
            logger.info(f"Response after callsign: {text[:80]}")

            if "Password:" in text:
                logger.info("Sending password")
                self.send(f"{self.password}\r")
                response = self.wait_and_collect(3.0)
                if response:
                    text = response.decode('latin-1', errors='replace')
                    logger.info(f"Response after password: {text[:80]}")

        # Send CHAT command
        logger.info("Sending CHAT command...")
        self.send("CHAT\r")

        # Wait for BPQChatServer banner
        response = self.wait_and_collect(5.0)
        if response:
            text = response.decode('latin-1', errors='replace')
            logger.info(f"Chat response: {text[:150]}")

            if "BPQChatServer" in text:
                logger.info("Got BPQChatServer banner!")
                self.in_chat = True
                self._record_event('entered_chat')

                # Send username
                logger.info(f"Sending username: {self.username}")
                self.send(f"{self.username}\r")

                # Read welcome message
                welcome = self.wait_and_collect(3.0)
                if welcome:
                    logger.info(f"Welcome: {welcome.decode('latin-1', errors='replace')[:200]}")

                return True
            else:
                logger.error(f"No BPQChatServer banner in response")

        logger.error("Failed to enter chat")
        self._record_event('chat_entry_failed')
        return False

    def check_status(self):
        """Check chat status with /p command."""
        self.send("/p\r")
        data = self.wait_and_collect(2.0)
        if data:
            text = data.decode('latin-1', errors='replace')
            logger.info(f"Status:\n{text}")
            self._parse_status_response(text)
            return text
        return None

    def _parse_status_response(self, text):
        """Parse the /p status response to extract node count and user list."""
        with self.state_lock:
            self.last_status_response = text

            # Parse node count from lines like "7 Node(s)"
            node_match = re.search(r'(\d+)\s+Node\(?s?\)?', text, re.IGNORECASE)
            if node_match:
                self.node_count = int(node_match.group(1))

            # Parse nodes from "Here T4CHAT <- T4CHAT TEST5- T1CHAT..." line
            here_match = re.search(r'Here\s+(\S+)\s+<-\s+(.+)', text)
            if here_match:
                nodes_str = here_match.group(2).strip()
                self.nodes_list = [n.strip() for n in nodes_str.split() if n.strip()]

            # Parse user list - look for "User X" or user@node patterns
            # Reset user list on each status update
            new_users = []
            for line in text.split('\n'):
                line = line.strip()
                # Match "User CALLSIGN" or similar patterns
                user_match = re.match(r'User\s+(\S+)', line)
                if user_match:
                    user = user_match.group(1)
                    new_users.append({'user': user, 'node': '', 'name': ''})

            if new_users:
                self.user_list = new_users

    def _parse_chat_line(self, line):
        """Parse a chat line and update state."""
        line = line.strip()
        if not line or line.startswith('\x01'):
            return

        # Parse chat messages - format: "USERNAME : message text"
        # The LinBPQ chat format uses " : " as separator
        # Note: All test clients use "CLIENT" as username, so we identify
        # the actual sender by the [CLIENT_ID] tag in the message text
        chat_match = re.match(r'^(\S+)\s*:\s+(.+)', line)
        if chat_match:
            from_user = chat_match.group(1)
            text = chat_match.group(2)

            # Skip our own messages (they echo back)
            # Check both the callsign and the CLIENT_ID embedded in text
            if from_user == self.callsign:
                return
            # Skip messages that contain our own CLIENT_ID tag
            if f'[{CLIENT_ID}]' in text:
                return
            with self.state_lock:
                self.messages_received.append({
                    'timestamp': time.time(),
                    'iso_time': datetime.utcnow().isoformat() + 'Z',
                    'from_user': from_user,
                    'from_node': '',  # LinBPQ doesn't include node in basic format
                    'text': text
                })
                self.messages_received_count += 1
                # Keep only last 500 messages
                if len(self.messages_received) > 500:
                    self.messages_received = self.messages_received[-500:]

    def send_chat_message(self, message):
        """Send a chat message."""
        if not self.in_chat:
            return False
        logger.info(f"Sending message: {message}")
        self.send(f"{message}\r")
        with self.state_lock:
            self.messages_sent += 1
        return True

    def run(self):
        """Main loop - stay connected and log events."""
        last_status = 0
        status_interval = 60  # Check status every 60 seconds
        last_message = 0
        message_count = 0
        # Calculate next message time with jitter
        next_message_delay = MESSAGE_INTERVAL + random.randint(-MESSAGE_JITTER, MESSAGE_JITTER)

        while True:
            # Connect if not connected
            if not self.connected or not self.in_chat:
                self.disconnect()

                if not self.connect():
                    logger.info(f"Waiting {RECONNECT_DELAY}s before retry...")
                    time.sleep(RECONNECT_DELAY)
                    continue

                if not self.login_and_enter_chat():
                    logger.error("Login/chat entry failed, reconnecting...")
                    self.disconnect()
                    time.sleep(RECONNECT_DELAY)
                    continue

                logger.info("Successfully connected to chat!")
                # Check status immediately after connecting
                self.check_status()
                last_status = time.time()

            # Check for API-requested status refresh
            if self.status_refresh_requested:
                self.status_refresh_requested = False
                self.check_status()
                last_status = time.time()

            # Check for API-requested message send
            with self.state_lock:
                if self.pending_message:
                    msg = self.pending_message
                    self.pending_message = None
            if 'msg' in dir() and msg:
                self.send_chat_message(msg)
                msg = None

            # Read any incoming data
            try:
                self.sock.settimeout(1.0)
                data = self.sock.recv(4096)
                if data:
                    text = data.decode('latin-1', errors='replace')
                    # Log interesting events, skip keepalives and empty lines
                    for line in text.split('\n'):
                        line_stripped = line.strip()
                        if line_stripped and not line_stripped.startswith('\x01'):
                            logger.info(f"CHAT: {line_stripped}")
                            self._parse_chat_line(line_stripped)
            except socket.timeout:
                pass  # Normal timeout, no data
            except Exception as e:
                logger.error(f"Recv error: {e}")
                self.connected = False
                continue

            # Periodic message sending
            now = time.time()
            if SEND_MESSAGES and self.in_chat and (now - last_message > next_message_delay):
                message_count += 1
                timestamp = time.strftime("%H:%M:%S")
                message = f"[{CLIENT_ID}] Test message #{message_count} at {timestamp}"
                self.send_chat_message(message)
                last_message = now
                # Recalculate next delay with jitter
                next_message_delay = MESSAGE_INTERVAL + random.randint(-MESSAGE_JITTER, MESSAGE_JITTER)
                logger.info(f"Next message in ~{next_message_delay}s")

            # Periodic status check
            if now - last_status > status_interval:
                logger.info("Periodic status check...")
                self.check_status()
                last_status = now


class ClientAPIHandler(BaseHTTPRequestHandler):
    """HTTP API handler for test queries."""
    client = None  # Set before server starts

    def log_message(self, format, *args):
        # Suppress default HTTP logging to reduce noise
        pass

    def send_json(self, data, status=200):
        """Send JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/health':
            self.send_json({
                'status': 'ok',
                'client_id': CLIENT_ID
            })

        elif self.path == '/status':
            with self.client.state_lock:
                self.send_json({
                    'client_id': CLIENT_ID,
                    'connected': self.client.connected,
                    'in_chat': self.client.in_chat,
                    'node_count': self.client.node_count,
                    'nodes_list': self.client.nodes_list.copy(),
                    'user_list': self.client.user_list.copy(),
                    'messages_sent': self.client.messages_sent,
                    'messages_received': self.client.messages_received_count,
                    'last_status': self.client.last_status_response,
                    'connection_history': self.client.connection_history[-10:]
                })

        elif self.path == '/messages':
            with self.client.state_lock:
                self.send_json({
                    'count': len(self.client.messages_received),
                    'messages': self.client.messages_received[-100:]
                })

        elif self.path.startswith('/messages/since/'):
            try:
                since = float(self.path.split('/')[-1])
                with self.client.state_lock:
                    filtered = [m for m in self.client.messages_received
                               if m['timestamp'] > since]
                    self.send_json({
                        'count': len(filtered),
                        'messages': filtered
                    })
            except ValueError:
                self.send_json({'error': 'Invalid timestamp'}, 400)

        else:
            self.send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        """Handle POST requests."""
        if self.path == '/send':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode() if content_length > 0 else ''
            try:
                data = json.loads(body) if body else {}
                message = data.get('message', f'API test at {time.time()}')

                if self.client.in_chat:
                    with self.client.state_lock:
                        self.client.pending_message = message
                    # Wait briefly for message to be sent
                    time.sleep(0.5)
                    self.send_json({'status': 'sent', 'message': message})
                else:
                    self.send_json({'error': 'Not in chat'}, 503)
            except json.JSONDecodeError:
                self.send_json({'error': 'Invalid JSON'}, 400)

        elif self.path == '/refresh_status':
            if self.client.in_chat:
                self.client.status_refresh_requested = True
                # Wait for status to be refreshed
                time.sleep(2.5)
                self.send_json({'status': 'refreshed'})
            else:
                self.send_json({'error': 'Not in chat'}, 503)

        else:
            self.send_json({'error': 'Not found'}, 404)

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()


def start_http_server(client, port):
    """Start HTTP API server."""
    ClientAPIHandler.client = client
    server = HTTPServer(('0.0.0.0', port), ClientAPIHandler)
    logger.info(f"HTTP API server started on port {port}")
    server.serve_forever()


def main():
    logger.info(f"Chat client starting...")
    logger.info(f"Host: {HOST}, Port: {PORT}")
    logger.info(f"Callsign: {CALLSIGN}, Username: {USERNAME}")
    logger.info(f"Client ID: {CLIENT_ID}")
    if SEND_MESSAGES:
        logger.info(f"Will send messages every {MESSAGE_INTERVAL}s (+/-{MESSAGE_JITTER}s jitter)")
    else:
        logger.info("Message sending disabled")

    # Wait a bit for LinBPQ to start
    startup_delay = int(os.environ.get('STARTUP_DELAY', '10'))
    logger.info(f"Waiting {startup_delay}s for LinBPQ to start...")
    time.sleep(startup_delay)

    client = ChatClient(HOST, PORT, CALLSIGN, PASSWORD, USERNAME)

    # Start HTTP API server in background thread
    http_thread = threading.Thread(
        target=start_http_server,
        args=(client, HTTP_PORT),
        daemon=True
    )
    http_thread.start()
    logger.info(f"HTTP API available on port {HTTP_PORT}")

    try:
        client.run()
    except KeyboardInterrupt:
        logger.info("Interrupted")
    finally:
        client.disconnect()

if __name__ == '__main__':
    main()
