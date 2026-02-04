# LinBPQ Chat Test Network

A Docker-based test network for developing tarpn-chat without affecting live networks.

## Network Topology

```
node1 (TEST1-1) <--AXUDP--> node2 (TEST2-1) <--AXUDP--> node3 (TEST3-1)
                                  |
                                  | AXUDP
                                  v
                           node4 (TEST4-1)
                           [custom tarpn-chat]
```

- **node1, node2, node3**: Run built-in LinBPQ chat
- **node4**: Runs tarpn-chat (our custom implementation)
- **node2**: Hub node connecting all others

## Port Mapping

| Node | Container | Telnet (host) | Web (host) | Chat SSID |
|------|-----------|---------------|------------|-----------|
| node1 | 172.20.0.2 | localhost:8011 | localhost:8081 | TEST1-9 |
| node2 | 172.20.0.3 | localhost:8012 | localhost:8082 | TEST2-9 |
| node3 | 172.20.0.4 | localhost:8013 | localhost:8083 | TEST3-9 |
| node4 | 172.20.0.5 | localhost:8014 | localhost:8084 | TEST4-9 |

## Quick Start

### 1. Build the x86_64 binary (not ARM)

```bash
# From tarpn-chat directory
cd ..
cargo build --release
cp target/release/tarpn-chat dist/tarpn-chat-x86_64
```

### 2. Update docker-compose for x86_64

Edit `docker-compose.yml` and change the tarpn-chat volume mount:
```yaml
- ../dist/tarpn-chat-x86_64:/opt/tarpn-chat/tarpn-chat:ro
```

### 3. Build and start the network

```bash
docker-compose build
docker-compose up -d
```

### 4. Check node status

```bash
# View logs
docker-compose logs -f

# Check if nodes are running
docker-compose ps
```

### 5. Connect to nodes via telnet

```bash
# Connect to node1
telnet localhost 8011

# At the login prompt, enter a callsign (e.g., TESTER)
# Then type: CHAT
# You should join the chat on TEST1-9
```

### 6. Test chat between nodes

Open multiple terminals:

**Terminal 1** (node1):
```bash
telnet localhost 8011
# Login as USER1
# Type: CHAT
# You're now in chat on node1
```

**Terminal 2** (node3):
```bash
telnet localhost 8013
# Login as USER2
# Type: CHAT
# You're now in chat on node3
```

Messages sent in one should appear in the other (after nodes discover each other).

### 7. Test node4 (custom chat)

```bash
# Start tarpn-chat manually first
docker-compose exec node4 /opt/tarpn-chat/tarpn-chat --config /opt/linbpq/config/tarpn-chat-config.toml &

# Then connect from another node
telnet localhost 8011  # Connect to node1
# Login, then: C TEST4-9  (connect to node4's chat)
```

## Debugging

### View LinBPQ logs

```bash
docker-compose exec node1 cat /opt/linbpq/bpq.log
```

### Check AXUDP connectivity

```bash
# From inside a container
docker-compose exec node1 nc -u 172.20.0.3 10093
```

### Watch tarpn-chat logs

```bash
docker-compose exec node4 tail -f /var/log/tarpn-chat.log
```

### Access web interface

Open in browser:
- http://localhost:8081 (node1)
- http://localhost:8082 (node2)
- http://localhost:8083 (node3)
- http://localhost:8084 (node4)

## Stopping

```bash
docker-compose down
```

## Clean rebuild

```bash
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
```

## Configuration Files

- `node1/bpq32.cfg` - Node1 LinBPQ config
- `node2/bpq32.cfg` - Node2 LinBPQ config (hub)
- `node3/bpq32.cfg` - Node3 LinBPQ config
- `node4/bpq32.cfg` - Node4 LinBPQ config (uses CMDPORT for chat)
- `node4/tarpn-chat-config.toml` - tarpn-chat config

## Troubleshooting

### Nodes not discovering each other

1. Check AXUDP ports are matching (node1 UDP 10093 -> node2 UDP 10093)
2. Verify IPs in MAP directives match docker-compose
3. Wait 60+ seconds for NODES broadcasts

### Chat not linking

1. Verify APPLICATION 2 line in bpq32.cfg
2. Check chat SSID routing (TEST1-9, TEST2-9, etc.)
3. On node4, ensure CMDPORT includes 63005 and tarpn-chat is running

### Connection refused to telnet

1. Check container is running: `docker-compose ps`
2. Check port mapping: `docker-compose port node1 8010`
3. View container logs: `docker-compose logs node1`
