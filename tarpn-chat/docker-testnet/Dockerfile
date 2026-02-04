# LinBPQ Docker image for test network
#
# This downloads and runs the official Linux LinBPQ binary.
# Note: LinBPQ is a 32-bit binary even on x86_64, so we need multiarch support.

FROM debian:bullseye-slim

ARG TARGETARCH

# Install dependencies
# LinBPQ is 32-bit even on amd64, so we need i386 libraries
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y \
    wget \
    libc6:i386 \
    libpcap0.8:i386 \
    zlib1g:i386 \
    && rm -rf /var/lib/apt/lists/*

# Create linbpq user and directories
RUN useradd -m -s /bin/bash linbpq && \
    mkdir -p /opt/linbpq /opt/tarpn-chat && \
    chown -R linbpq:linbpq /opt/linbpq /opt/tarpn-chat

WORKDIR /opt/linbpq

# Download LinBPQ binary based on architecture
# x86_64: linbpq (64-bit Intel/AMD)
# arm: pilinbpq (32-bit ARM for Raspberry Pi)
# Check https://www.cantab.net/users/john.wiseman/Downloads/Beta/ for latest
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        wget -q https://www.cantab.net/users/john.wiseman/Downloads/Beta/linbpq && \
        chmod +x linbpq; \
    elif [ "$TARGETARCH" = "arm" ] || [ "$TARGETARCH" = "arm64" ]; then \
        wget -q https://www.cantab.net/users/john.wiseman/Downloads/Beta/pilinbpq && \
        chmod +x pilinbpq && \
        ln -s pilinbpq linbpq; \
    else \
        echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi

# Create necessary directories
RUN mkdir -p /opt/linbpq/config /opt/linbpq/HTML

# Create startup script that copies config and runs linbpq
RUN echo '#!/bin/sh\n\
cp /opt/linbpq/config/bpq32.cfg /opt/linbpq/bpq32.cfg 2>/dev/null || true\n\
cp /opt/linbpq/config/linmail.cfg /opt/linbpq/linmail.cfg 2>/dev/null || true\n\
cp /opt/linbpq/config/chatconfig.cfg /opt/linbpq/chatconfig.cfg 2>/dev/null || true\n\
exec /opt/linbpq/linbpq\n' > /opt/linbpq/start.sh && \
    chmod +x /opt/linbpq/start.sh

# Expose ports
# 8010 = Telnet
# 8080 = Web interface
# 10093-10095 = AXUDP (internal network)
# 63005 = tarpn-chat listener
EXPOSE 8010 8080 10093/udp 10094/udp 10095/udp 63005

# Run as root for now (LinBPQ sometimes needs it for raw sockets)
# USER linbpq

# Start LinBPQ via startup script
CMD ["/opt/linbpq/start.sh"]
