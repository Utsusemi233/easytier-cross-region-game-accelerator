# Agent instructions

Read `README.md`, `docs/DEPLOY.md`, `docs/COMPATIBILITY.md`, and `docs/ACCEPTANCE.md` before touching a router. This is an additive extension of EasyTier's existing LuCI menu, not a replacement EasyTier management application.

## Choose the access mode

- The main mode is an OpenWrt access gateway that routes selected traffic from devices on its accelerated network through an authorized regional exit. The current gateway scripts deploy an fw4 OpenWrt access side and an fw3 OpenWrt exit side; this implementation scope does not define every possible exit platform.
- An independent computer uses the official EasyTier client and its own native connection profile. Read `docs/WINDOWS-TRAVEL.md` and `docs/PORTABLE-AI-PROMPT.md`; do not run the router installation workflow on a PC. The exit must expose a matching native EasyTier entry. A WireGuard pairing export is not a native EasyTier profile, and native PC access does not automatically include UDPspeeder FEC.
- A computer can also connect to a native entry on an existing OpenWrt policy gateway and reuse that gateway's FEC backend. Read `docs/NATIVE-GATEWAY.md` and `docs/DEPLOYMENT-LESSONS.md`. This version supplies reference templates and manual integration steps; `scripts/install.sh` does not deploy that bridge automatically. Inspect the existing classifier, underlay exclusions, policy table, forward/NAT and reload lifecycle before changing them.
- Nodes in the same EasyTier network share its name/secret. The 2.6.4 reference client can omit `instance_id`/`ipv4` and use `dhcp=true`; do not ask users to hand-fill separate accounts or addresses. Verify assigned addresses, and do not clone a fixed-address restore profile or a router's WireGuard/ZeroTier device identity.
- Linux hosts and suitable NAS devices are possible exit platforms with separately configured services and forwarding. This repository does not currently automate or claim acceptance for those deployments. Distinguish the exit host from the application server, and report direct versus relayed paths accurately.
- For computer access, read `docs/NETWORK-ROAMING.md`. Changing Wi-Fi, hotspots or physical IP addresses must not require the user to rewrite the profile. Separate underlay roaming, virtual DHCP and remote endpoint changes. Check current physical interface/gateway and owned bypass routes after a switch; do not treat an unbound interface or LAN success as roaming acceptance. Use the official client and existing components, without inventing a replacement UI or unrequested Windows monitor. The optional `windows/` component targets the official-client -> authorized ZeroTier -> existing native-gateway IPv4 mode. Install it only when requested, after inspecting its plan. Preserve the official UI. Verify recent status, owned routes, fallback and reconnection; do not generalize it to arbitrary hotspots, IPv6-only underlays or direct-exit profiles.

## OpenWrt gateway workflow

1. Collect the router roles, firmware/firewall versions, existing accelerated network, binaries, global WAN IPv6 and authorized address-discovery peer identity. Do not infer compatibility from an upstream package's version claims.
2. For an existing codex-game prototype, use `et-game adopt` to populate the real role and discovery configuration first, then run `et-game doctor`. For new routers fill the configuration before doctor. Preserve existing WireGuard identity, SSIDs, IPv6 relay, application DNS and FEC settings.
3. Fill `/etc/config/easytier_home_game` using the example config. Run `et-game plan`; inspect its scope before `et-game apply`.
4. For a new pair, deploy home first and transfer its pairing profile privately. Never print or commit WireGuard private keys, router credentials, ZeroTier identities, pairing exports or unredacted router backups.
5. Run `et-game verify` on both sides, inspect structured failures, test ordinary Internet separately, and use `docs/ACCEPTANCE.md` for recovery tests. A service process, a stale successful probe, or an interface being up is not acceptance.
6. Report tests as passed, failed, or not performed. Never turn the case study into a universal latency promise. Record FEC bandwidth costs and both-side configuration consistency.

## Commands and checks

- Local source checks: `node tests/check-source.mjs`.
- Hotplug checks: `sh tests/endpoint-hotplug.sh`; these redirect the wake file to a temporary directory and mock UCI, without changing a live network. Check the TOML examples with the matching official 2.6.4 binary's `--check-config`; this validates parsing, not actual routing or deployment.
- Device tests: `lua /usr/libexec/codex-game/test-endpoint-common.lua`; `et-game doctor`; `et-game verify`.
- Read-only diagnostics precede mutations. Changes must have a concrete plan and a backup; restore only files/rules owned by this project.
- Use Lua 5.1, BusyBox POSIX shell, and ES5 browser JavaScript in the LuCI extension. Follow the upstream Lua controller / template approach; do not introduce React/Vue or a second web server.
- Before changing the UI, read `docs/DESIGN.md`. Match the installed LuCI theme; verify actual browser feedback, keyboard/error focus and mobile screenshots. Preserve drafts during polling.
- Rule acceptance requires stored-content readback, actual nft expressions and policy routing, disabled/deleted-rule removal, and matching device traffic counters. Saving is not application; a matched packet is not a measured game-speed improvement. Run `lua tests/device-manager.lua` on compatible devices after model changes.
- The public repository excludes `work/`, local credentials and private case-study notes. Build artifacts and runtime backups are ignored.

## First-version limits

The current scripts target an fw4 client and an fw3 exit gateway, using EasyTier 2.4.5 reference interfaces and UDPspeeder V2. Every actual firmware, architecture and installation must be checked independently before being labelled verified. The current automatic native IPv6 discovery also depends on ZeroTier; public EasyTier relay nodes do not automatically provide authorized Internet exit service. Never publish an owner's addresses, identities, screenshots with live data, or personal measurement records. Public screenshots use clearly labelled demonstration data.

## Writing

Use `academic-humanizer` when available to review repository prose. Keep technical terms, references and numbers, use direct sentences, and match claims to evidence. The skill is an editing aid, not a runtime dependency. Do not turn configuration examples, temporary probes or an owner's measurements into general performance guarantees; keep missing acceptance checks explicit.


## Optional direct-exit Windows mode

Read docs/DIRECT-HOME.md and manual/README.md before deploying this optional path. It retains the official GUI, connects a local UDPspeeder to the authorized exit's native EasyTier entry, and does not require the original access gateway. Use windows/Install-DirectHomeRecovery.ps1 only with a reviewed private config and explicit deployment authorization. Do not enable the older gateway-mode task at the same time for the same TUN. Home reference files in home-direct/ require configuration and manual scope review; the main router install script does not install this path automatically.

Check current physical IPv4/IPv6, gateway, virtual DHCP address, ownership journals and fresh virtual-gateway plus bound IPv4 HTTPS proof. If ICMP fails, gateway DNS/TCP and bound HTTPS must both succeed. Individually bind the exit's global IPv6 UDP sockets, preserving reply source. Record live failure and recovery checks separately from isolated tests, and distinguish same-SSID reconnection from a new hotspot, alias/signature changes from ISP prefix reassignment, and task restart from full boot. Preserve old working gateway services and private restore profiles. Do not publish an owner's test records.
