# linksy-server: iroh's relay, pinned, as one static binary on an empty image.
# It introduces Linksy devices to each other and tells each its public address; it
# relays only a trickle (see relay.toml) and stores nothing but its TLS certificate.

ARG IROH_RELAY_VERSION=1.4.0
# Which configuration goes in the image: relay.tunnel.toml (behind a tunnel, the default)
# or relay.toml (standalone, from relay.example.toml). Built in, not mounted: a mounted
# file the relay can't read (SELinux, say) makes it start silently with its defaults.
ARG CONFIG=relay.tunnel.toml

FROM rust:1.91-alpine AS build
ARG IROH_RELAY_VERSION
RUN apk add --no-cache musl-dev ca-certificates perl
# The upstream relay at an exact version, from crates.io with its lockfile. One change:
# its front page (a constant in server.rs) becomes Linksy's index.html. The build stops
# if that constant ever moves, rather than shipping iroh's page by mistake.
COPY index.html /linksy/index.html
RUN wget -qO- "https://crates.io/api/v1/crates/iroh-relay/${IROH_RELAY_VERSION}/download" | tar xz -C /tmp \
 && cd "/tmp/iroh-relay-${IROH_RELAY_VERSION}" \
 && grep -q 'const INDEX: &\[u8\] = br#"' src/server.rs \
 && perl -0pi -e 's/const INDEX: &\[u8\] = br#".*?"#;/const INDEX: &[u8] = include_bytes!("\/linksy\/index.html");/s' src/server.rs \
 && grep -q 'include_bytes!("/linksy/index.html")' src/server.rs \
 && cargo install --path . --features server --locked --root /out \
 && strip /out/bin/iroh-relay
RUN mkdir -p /out/state/certs && chown -R 65534:65534 /out/state

FROM scratch
ARG CONFIG
COPY ${CONFIG} /etc/linksy-relay/relay.toml
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/bin/iroh-relay /iroh-relay
COPY --from=build --chown=65534:65534 /out/state /var/lib/linksy-relay
# Nobody: no root, no shell, nothing else in the image.
USER 65534:65534
# Warnings only: no per-connection logs, so no IP addresses on disk.
ENV RUST_LOG=warn
EXPOSE 80/tcp 443/tcp 7842/udp
ENTRYPOINT ["/iroh-relay", "--config-path", "/etc/linksy-relay/relay.toml"]
