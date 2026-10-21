# linksy-server: iroh's relay, pinned, as one static binary on an empty image.
# It introduces Linksy devices to each other and tells each its public address; it
# relays only a trickle (see relay.toml) and stores nothing but its TLS certificate.

ARG IROH_RELAY_VERSION=1.4.0

FROM rust:1.91-alpine AS build
ARG IROH_RELAY_VERSION
RUN apk add --no-cache musl-dev ca-certificates
# Static build of the upstream relay at an exact version, from crates.io's lockfile.
RUN cargo install iroh-relay --version "=${IROH_RELAY_VERSION}" --features server --locked --root /out \
 && strip /out/bin/iroh-relay
RUN mkdir -p /out/state/certs && chown -R 65534:65534 /out/state

FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/bin/iroh-relay /iroh-relay
COPY --from=build --chown=65534:65534 /out/state /var/lib/linksy-relay
# Nobody: no root, no shell, nothing else in the image.
USER 65534:65534
# Warnings only: no per-connection logs, so no IP addresses on disk.
ENV RUST_LOG=warn
EXPOSE 80/tcp 443/tcp 7842/udp
ENTRYPOINT ["/iroh-relay", "--config-path", "/etc/linksy-relay/relay.toml"]
