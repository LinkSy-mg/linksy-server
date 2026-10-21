# linksy-server

The relay that lets Linksy devices find each other away from home. It is
[iroh's relay](https://github.com/n0-computer/iroh) at a pinned version, built as one
static binary on an empty container image, with Linksy's settings.

It doesn't carry your data. Linksy is also not using it yet: the desktop and phone
apps will use it from Linksy 0.6 ("away from home"). This repository is the server side,
ready to deploy.

## What it does

| Job | Traffic |
|---|---|
| **Introduces** two paired devices so they can connect directly (hole punching) | A few KB per meeting |
| **Answers "what's my public address?"** over QUIC (port 7842/udp) | One small packet |
| **Relays a trickle** when two networks block a direct connection | At most 16 KiB/s per device, bursts of 256 KiB |

Files, screens, cameras and microphones always go **directly** between the devices. The
trickle is enough for what's small (clipboard text, Ring, battery, links, notifications)
and makes the relay useless for anything heavy. A device that can only reach the other
through the relay says so instead of trying.

## What it sees, and what it doesn't

Everything between two devices is encrypted end to end (QUIC, TLS 1.3, keys pinned when
they paired). The relay has no keys.

| Visible to the relay | Never visible |
|---|---|
| Random device keys (no names, no accounts: there are none) | Device names, files, clipboard, screens, camera, microphone |
| IP addresses of connected devices | What was shared, or with whom by name |
| How many bytes it relayed | Encryption keys |

It **logs warnings only** (`RUST_LOG=warn`): no per-connection lines, so no IP addresses
on disk. It **stores nothing** but its TLS certificate. Metrics are totals only and
listen on `127.0.0.1` of the host.

## Deploy

You need a small Linux server with a public IP (1 vCPU, 512 MB is plenty), Docker with
Compose v2.23 or newer, and a DNS name for it.

1. Point a DNS record (A, and AAAA if the server has IPv6) at the server, for example
   `relay.linksy.diary.mg`.
2. Open ports **80/tcp, 443/tcp and 7842/udp** in the firewall.
3. Configure and start:

   ```sh
   git clone <this repository> linksy-server && cd linksy-server
   cp relay.example.toml relay.toml    # set hostname and contact
   docker compose up -d --build
   ```

   The first start gets a Let's Encrypt certificate (port 80 must be reachable).

4. Check it:

   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' https://relay.linksy.diary.mg/ping   # 200
   curl -s 127.0.0.1:9090/metrics | grep -E '^relayserver_(accepts|bytes_)'
   docker compose logs -f relay                                                 # warnings only
   ```

Upgrade: change `IROH_RELAY_VERSION` in the `Dockerfile` (and the image tag in
`compose.yaml`), then `docker compose up -d --build`. Linksy apps and the relay must use
compatible iroh versions; the apps' release notes say which.

## Hardening

The container runs as `nobody` on an empty image (no shell, no package manager, nothing
but the binary and CA certificates), with a **read-only** filesystem, **every Linux
capability dropped**, `no-new-privileges`, and limits on memory (256 MB), CPU (1),
processes (256) and log size. Ports 80 and 443 are opened to the unprivileged user
through the container's own `ip_unprivileged_port_start` network sysctl, not by a
capability. The only writable path is the certificate volume; the configuration is
mounted read-only.

## Tuning

In `relay.toml`, then `docker compose up -d`:

| Setting | Default | Meaning |
|---|---|---|
| `limits.client.rx.bytes_per_second` | 16384 | What one device may relay per second |
| `limits.client.rx.max_burst_bytes` | 262144 | What it may relay at once (one clipboard) |
| `limits.accept_conn_limit` | 50.0 | New connections per second, whole server |
| `limits.accept_conn_burst` | 200 | New connections in a burst |

Sizing, with the trickle: traffic is introductions, address answers and small messages,
so one 5 EUR VPS (20 TB/month) has room for far more users than it will have. Watch
`relayserver_bytes_recv_total` and `relayserver_bytes_rx_ratelimited_total` (how much the
trickle held back) in the metrics.

## Self-hosting

Anyone can run their own copy and point Linksy at it in Preferences (Linksy 0.6), instead
of the default `relay.linksy.diary.mg`.

## Try it on your computer

`compose.dev.yaml` runs it over plain HTTP on `localhost:3340` with no certificate:

```sh
docker compose -f compose.dev.yaml up --build
curl -s -o /dev/null -w '%{http_code}\n' localhost:3340/ping   # 200
```
