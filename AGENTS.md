# Agent instructions

Read `README.md`, `docs/DEPLOY.md`, `docs/COMPATIBILITY.md`, and `docs/ACCEPTANCE.md` before touching a router. This is an additive extension of EasyTier's existing LuCI menu, not a replacement EasyTier management application.

## Workflow

1. Collect the router roles, firmware/firewall versions, existing accelerated network, binaries, global WAN IPv6 and authorized address-discovery peer identity. Do not infer compatibility from an upstream package's version claims.
2. For an existing codex-game prototype, use `et-game adopt` to populate the real role and discovery configuration first, then run `et-game doctor`. For new routers fill the configuration before doctor. Preserve existing WireGuard identity, SSIDs, IPv6 relay, application DNS and FEC settings.
3. Fill `/etc/config/easytier_home_game` using the example config. Run `et-game plan`; inspect its scope before `et-game apply`.
4. For a new pair, deploy home first and transfer its pairing profile privately. Never print or commit WireGuard private keys, router credentials, ZeroTier identities, pairing exports or unredacted router backups.
5. Run `et-game verify` on both sides, inspect structured failures, test ordinary Internet separately, and use `docs/ACCEPTANCE.md` for recovery tests. A service process, a stale successful probe, or an interface being up is not acceptance.
6. Report tests as passed, failed, or not performed. Never turn the case study into a universal latency promise. Record FEC bandwidth costs and both-side configuration consistency.

## Commands and checks

- Local source checks: `node tests/check-source.mjs`.
- Device tests: `lua /usr/libexec/codex-game/test-endpoint-common.lua`; `et-game doctor`; `et-game verify`.
- Read-only diagnostics precede mutations. Changes must have a concrete plan and a backup; restore only files/rules owned by this project.
- Use Lua 5.1, BusyBox POSIX shell, and ES5 browser JavaScript in the LuCI extension. Follow the upstream Lua controller / template approach; do not introduce React/Vue or a second web server.
- Before changing the UI, read `docs/DESIGN.md`. Match the installed LuCI theme; verify actual browser feedback, keyboard/error focus and mobile screenshots. Preserve drafts during polling.
- Rule acceptance requires stored-content readback, actual nft expressions and policy routing, disabled/deleted-rule removal, and matching device traffic counters. Saving is not application; a matched packet is not a measured game-speed improvement. Run `lua tests/device-manager.lua` on compatible devices after model changes.
- The public repository excludes `work/`, local credentials and private case-study notes. Build artifacts and runtime backups are ignored.

## First-version limits

The current scripts target an fw4 client and an fw3 exit gateway, using EasyTier 2.4.5 reference interfaces and UDPspeeder V2. Every actual firmware, architecture and installation must be checked independently before being labelled verified. The current automatic native IPv6 discovery also depends on ZeroTier; public EasyTier relay nodes do not automatically provide authorized Internet exit service. Never publish an owner's addresses, identities, screenshots with live data, or personal measurement records. Public screenshots use clearly labelled demonstration data.
