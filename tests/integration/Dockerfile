FROM debian:bookworm-slim

# один образ для server и client контейнеров
RUN apt-get update && apt-get install -y --no-install-recommends \
    openvpn \
    openssl \
    jq \
    curl \
    procps \
    iputils-ping \
    iproute2 \
    libpam-google-authenticator \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
