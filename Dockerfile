FROM ubuntu:22.04

# Pre-install mesh lab tools at build time (host has internet).
# Macvlan MANET containers cannot reach apt mirrors at runtime.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        batctl \
        iproute2 \
        iputils-ping \
        iperf3 \
        tcpdump \
        kmod \
    && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
