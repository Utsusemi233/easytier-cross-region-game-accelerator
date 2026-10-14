# Experimental in-core FEC for Windows Clash

This optional patch places a UDPspeeder V2 mode-0 compatible transport inside Mihomo's EasyTier outbound. Keep the existing Clash GUI. The client does not run a separate UDPspeeder process; the authorized exit still needs matching UDPspeeder and native EasyTier services, forwarding and NAT.

Build from the pinned Mihomo v1.19.32 commit in `source-metadata.json` with `Build-MihomoFEC.ps1`. The extension version is `v1.19.32-fec.4`. Keep the official stable core and previous profile for rollback. Service-mode Clash Verge clients must register the candidate through their official core installation interface, then verify the running `/version`. Replacing the executable beside the GUI alone does not update the protected service copy.

`type: easytier-fec` requires this patched core. Stock cores reject it. This Windows amd64 build is not an Android or Shadowrocket configuration. The template routes selected game UDP through FEC; use a separate authorized ordinary route for TCP login, downloads and application DNS when needed. TUN or native application proxy support is required to capture game UDP.

The Windows transport selects an eligible physical interface at runtime. It excludes virtual interfaces and requires a valid address and gateway for the configured family. The profile keeps a dynamic peer hostname, DHCP and a local state directory; do not clone another client's instance state. Physical signatures are checked every five seconds, peer DNS every fifteen seconds, with stable-change confirmation before rebuilding this node. Old application UDP sockets are closed on instance retirement or peer removal so Clash can release their NAT mappings. These intervals do not guarantee total recovery time or uninterrupted game sessions.

Native interoperability, controlled stale-DNS recovery, physical-interface alias changes and TCP/UDP idle/reopen checks have been exercised. Earlier rounds and application recovery still contain failures or incomplete acceptance. Different hotspots, real ISP prefix changes, multiple physical interfaces and post-change game sessions require separate tests. Public documentation includes no owner's addresses or measurements; keep deployment evidence private.

The example's `2:30`, 1 ms batching and 5 ms dispersion are high-redundancy experimental settings. They can increase packet volume sixteenfold or more, with additional framing and padding costs. Do not apply this path to large downloads or assume it is the best setting for every link. Use the exposed FEC counters and real application measurements.

The complete Chinese instructions are in [README.md](README.md). Preserve [Mihomo's GPL license](LICENSE.MIHOMO) and [UDPspeeder/Rizzo attribution](overlay/component/udpspeeder/NOTICE.md) when distributing modified binaries. The build script provides corresponding source; it does not install an exit or grant access to another network.

## Recovery from a running instance with an unavailable data path

`fec.4` handles persistent overlay `ENETUNREACH` or `ENETRESET` errors from TCP and application UDP operations. After at least two errors lasting ten seconds, and a thirty-second startup grace period, the next five-second check rebuilds only this node. A successful TCP connection or received UDP packet cancels pending recovery. Destination timeouts, refused connections, cancelled callers and results from retired instances do not trigger it. This adds no external probing service.

The local identity survives rebuilding, and old UDP mappings are released. The API exposes `path-route-failures`, `path-restarts` and `last-restart-reason`. These thresholds limit restarts rather than guaranteeing recovery time. Isolated testing covers an interruption with an unchanged peer address, a restored real exit and preserved identity; actual game-session recovery and different hotspots remain separate acceptance items.

## Keep domain fallbacks out of the download path

Process rules alone are insufficient. An unconditional game-domain rule can send TCP login, web components or resource downloads into FEC when process lookup fails. Restrict the domain fallback with `AND,((NETWORK,UDP),(DOMAIN-SUFFIX,...)),Game route`, and send TCP through an authorized ordinary route.

A separate `select` group can let the operator choose the local exit or an ordinary TCP proxy for a resource CDN. Keep it separate from game failover and exclude DIRECT from automatic candidates. Validate actual transferred bytes and the game's update stage; a small HEAD response does not establish that full downloads work.

This extension dials a native EasyTier entry and applies the matching outer UDP FEC format. It does not use Hysteria2 Realm coordination. The IPv6 example requires a reachable IPv6 underlay and server-side address binding/DDNS. Success on a separate Realm profile does not establish IPv4-only hotspot support here.
