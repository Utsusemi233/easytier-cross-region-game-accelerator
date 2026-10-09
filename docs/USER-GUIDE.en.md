# EasyTier Cross-Region Game Accelerator — User Guide

**An EasyTier-based cross-region game acceleration toolkit for OpenWrt routers.**

The main repository content and current LuCI interface remain in Chinese. This guide explains the project in English. It contains no owner's addresses, credentials, or personal test results.

## 1. What this project does

Connect an OpenWrt router in one country or region to a broadband exit you control in another. Selected game or application traffic uses that exit; other traffic keeps its local route. The project integrates EasyTier, WireGuard, UDPspeeder forward error correction, selective routing, endpoint discovery, and a LuCI management page.

It is not limited to connecting to China. Choose an authorized exit in a region appropriate for the application. A shorter or more reliable route may help, but an extra tunnel can also make a connection slower. Measure your own connection before keeping a rule enabled.

This is a source preview, not a hosted VPN service. No public exit is included. You provide both endpoints and their Internet connections. A commercial game accelerator subscription is not required for a self-hosted setup, but equipment, broadband, and error-correction traffic still have costs.

## 2. Requirements and limits

- Administrative access to both OpenWrt routers and permission to use the exit connection.
- Reachable global IPv6 addresses for the current router-to-router FEC transport.
- EasyTier, WireGuard, UDPspeeder V2, and binaries matching each router's CPU architecture.
- The access router currently needs fw4/nftables, WireGuard kernel support, Lua 5.1, the LuCI Lua compatibility layer, `ip`, `curl`, and `conntrack`.
- The exit router currently needs fw3/iptables, TUN support, Lua 5.1, `ip`, and `curl`.
- Current automatic endpoint discovery uses authenticated peer paths in your own ZeroTier network. Both discovery peers must be authorized, and their identities must be fixed in the configuration.

See [compatibility](COMPATIBILITY.md). Other firewall combinations, architectures, IPv4-only FEC transport, complete prefix changes, and multiple access routers need separate adaptation and acceptance checks. Do not install another firmware's kernel modules merely because a package name matches.

Rules select destination IPv4 addresses and ports. Automatic discovery of every application's servers and destination IPv6 policy routing are not complete features of this version. APNIC allocation records, if used in an independent PC setup, indicate address registration regions rather than application ownership.

## 3. How the router path works

```text
Selected traffic in region A
  -> WireGuard
  -> UDPspeeder FEC over global IPv6
  -> authorized exit in region B
  -> EasyTier WireGuard portal
  -> exit broadband
  -> application server

Unselected traffic -> region A's local Internet connection
```

The two FEC endpoints must use matching parameters. Keep existing working identities, wireless networks, IPv6 settings, and application rules when adopting an existing deployment.

## 4. Install the LuCI extension

Read [AGENTS.md](../AGENTS.md) and [deployment instructions](DEPLOY.md) before making network changes. Back up both routers first.

Install the upstream `luci-app-easytier` and required dependencies. Build the `openwrt/` package using a compatible OpenWrt SDK, or use the source installation procedure for evaluation:

```sh
sh scripts/install.sh --plan
sh scripts/install.sh --install
```

The preview does not include an IPK that is claimed to have completed SDK build acceptance. Review the installation plan. It must not replace your WAN or wireless configuration.

The page extends the existing **VPN → EasyTier** menu. The Chinese entry **跨地区游戏加速** means “Cross-region game acceleration.” It does not start a second web server or replace EasyTier's original management pages.

Legacy internal package, UCI, and file identifiers containing `home-game` remain for upgrade compatibility. The public project name is **EasyTier Cross-Region Game Accelerator**.

## 5. Configure and deploy the two sides

Use [example configurations](../examples/) as templates. They are examples, not live credentials. Set real values privately on your own equipment.

1. Identify the access and exit roles, actual firmware/firewall versions, accelerated network, binary paths, global IPv6 addresses, and fixed authorized discovery peers.
2. Configure the exit side first. The internal role value `home` means the authorized exit; it can be in any suitable region.
3. On each side, run the prerequisite check and inspect the plan before applying:

   ```sh
   et-game doctor
   et-game plan
   et-game apply
   et-game verify
   ```

4. Transfer the exit's pairing profile privately. It may contain a WireGuard private key:

   ```sh
   # Exit router
   et-game export-profile /tmp/exit.private.pair.json

   # Access router, after private transfer
   et-game import-profile /tmp/exit.private.pair.json
   ```

5. Confirm that each client has its own unused address and identity. Review the plan again after import, then apply and verify.
6. If adopting a running project prototype, first run `et-game adopt`. It reads existing settings rather than generating new tunnel identities.

Do not publish pairing files, secrets, keys, unredacted backups, or real endpoint addresses in Issues or screenshots. Remove temporary pairing exports after private transfer and verification.

## 6. Use the management page

| Chinese label | Meaning |
| --- | --- |
| 运行状态 | Runtime status |
| 加速规则 | Routing rules |
| 线路设置 | Connection settings |
| 诊断 | Diagnostics |
| 仅保存 | Save the draft only |
| 保存并应用 | Save, apply, and verify |
| 验证当前线路 | Run a fresh connection check |
| 暂停家庭分流 | Pause routing through the exit |
| 恢复家庭分流 | Resume after fresh verification |

Add a rule for a device within the configured accelerated network, a destination IPv4 CIDR, protocol, and optional ports. Finish editing, then use **保存并应用** to deploy it.

“Saved,” “loaded,” and “matched” are different states. Saving alone does not change runtime rules. Loaded rules must match the real firewall expressions and policy routes. Packet counters show that matching traffic occurred; they do not prove a game became faster. Restart an application after a route change so it creates fresh connections.

The page keeps unsaved drafts during polling, shows operation progress and errors, and distinguishes a verified exit from local fallback. Invalid inputs should remain visible for correction rather than disappearing.

## 7. Endpoint recovery and failure handling

The monitor only trusts the configured discovery peer's fresh authenticated paths. It updates changed global IPv6 endpoints and actively verifies the new exit. A running process or an interface marked UP is not sufficient.

If an exit check fails or expires, selected routing should fall back locally. Use:

```sh
et-game status
et-game doctor
et-game verify
et-game pause
et-game resume
et-game backup
et-game rollback BACKUP_ID
```

Rollback must restore this project's own files and rules without deleting unrelated VPN, firewall, DNS, or wireless settings. Inspect failures before applying another change.

## 8. Validate your own deployment

Use [acceptance methods](ACCEPTANCE.md) and record passed, failed, and not-performed checks privately:

- The active endpoint belongs to the intended peer and is reachable.
- A fresh tunnel probe and an HTTPS request bound to the tunnel both succeed.
- The public exit actually matches the intended connection.
- Selected traffic uses the expected firewall and policy route; ordinary traffic remains local.
- IPv6 and existing application DNS remain functional.
- Pausing releases the selected route; resuming requires a new successful check.
- Endpoint changes, service failure, and reboot recovery are checked separately.
- Game latency, loss, jitter, and bandwidth are measured in the same device/server/scenario with routing off and on.

Do not publish personal test logs. Do not label an untested country, hotspot, prefix change, or firmware as verified.

## 9. Error-correction cost

More redundancy increases bandwidth. For a mathematical `2:30` example, every two data packets have thirty redundant packets: sixteen times the total packet count, or 1,500% additional packets. A `20:10` example gives 1.5 times the packet count. Actual bytes also depend on padding and encapsulation.

Neither example is a universal recommendation. Start with parameters appropriate for the connection, keep both sides consistent, and measure extra traffic before increasing redundancy.

## 10. A computer away from the router

The router's rules apply only to devices using its network. For a laptop on another network, install the **official EasyTier GUI** from the [official download page](https://easytier.cn/guide/download.html). Keep its configuration private and allocate a unique virtual address and instance identity.

An independent native EasyTier client needs its own acceptance checks. It does not automatically include the router's UDPspeeder FEC path. Stop conflicting old services before starting a GUI profile with the same address. Exclude tunnel interfaces and tunnel subnets from the underlay so a tunnel cannot become its own transport.

See [Windows notes](WINDOWS-TRAVEL.md) and [the AI handoff prompt](PORTABLE-AI-PROMPT.md). The public repository does not contain preconfigured access to an owner's exit.

## 11. Public learning resources

[VPN Gate](https://www.vpngate.net/en/) offers a public volunteer VPN project for learning about VPN protocols and connections. **This project does not guarantee its effectiveness, availability, or safety. Use it cautiously.** It is separate from EasyTier, is not configured as a default peer, and is not a guaranteed free exit in the region you need.

See [public resources](PUBLIC-RESOURCES.md). Shared EasyTier relays, Internet exits, and third-party VPN services are different capabilities; permission and actual exit verification still matter.

## 12. Attribution

EasyTier, WireGuard, UDPspeeder, and ZeroTier provide the underlying protocols and algorithms. This project contributes deployment integration, routing management, recovery checks, and LuCI controls. New project code is licensed under Apache-2.0; third-party components retain their own licenses.
