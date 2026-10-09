# EasyTier Cross-Region Game Accelerator: User Guide

**An EasyTier-based cross-region game access toolkit focused on OpenWrt gateway routing.**

The main repository content and current LuCI interface remain in Chinese. This guide explains the project in English. It contains no owner's addresses, credentials, or personal test results.

## 1. What this project does

Send selected local game or application traffic through a tunnel to an authorized exit in another country or region, then use that exit's Internet connection to reach the application server. An exit can be a home broadband gateway or a public server you control and configure for forwarding.

The main mode uses a local OpenWrt router to manage selected traffic from devices on its accelerated network. It integrates EasyTier, WireGuard, UDPspeeder forward error correction, selective routing, endpoint discovery, and a LuCI management page. Devices using that network share the gateway connection without installing their own tunnel clients; unselected traffic keeps its local route.

A computer can also use the official EasyTier client to access a matching native exit entry independently of the local router. This repository provides configuration and AI deployment guidance for that mode. Native computer access does not automatically include the gateway's UDPspeeder FEC path. A computer can instead connect to a native entry on an existing OpenWrt policy gateway and reuse its working backend. Reference profiles and manual integration steps are provided; the installer does not deploy that bridge automatically.

It is not limited to connecting to China. Choose an authorized exit in a region appropriate for the application. A shorter or more reliable route may help, but an extra tunnel can also make a connection slower. Measure your own connection before keeping a rule enabled.

This is a source preview, not a hosted VPN service. No public exit is included. You provide the access network and an authorized exit. A commercial game accelerator subscription is not required for a self-hosted setup, but equipment, Internet access, exit hosting, and error-correction traffic still have costs.

## 2. Access modes, requirements, and limits

| Access mode | Traffic scope | What this repository provides |
| --- | --- | --- |
| OpenWrt gateway, the main mode | Selected devices and destinations within the accelerated network | LuCI controls, gateway deployment, WireGuard + UDPspeeder FEC, endpoint updates, and exit verification |
| Independent computer client | Traffic from that computer, according to its native client routes | Official EasyTier GUI setup and AI instructions, with separate acceptance checks |
| Computer through an existing FEC gateway | IPv4 handed to the gateway, which selects regional or local forwarding | Automatic-address client and native-gateway templates, manual routing/NAT integration, and acceptance steps |

The exit receives tunnel traffic and forwards it through the target region's Internet connection. Compatible routers, Linux hosts, or suitable NAS devices can perform that role with separately configured services and forwarding. The current automated gateway deployment targets an OpenWrt access side and an OpenWrt exit side, with these requirements:

- Administrative access to the OpenWrt access and exit gateways and permission to use the exit connection.
- Reachable global IPv6 addresses for the current router-to-router FEC transport.
- EasyTier, WireGuard, UDPspeeder V2, and binaries matching each router's CPU architecture.
- The access router currently needs fw4/nftables, WireGuard kernel support, Lua 5.1, the LuCI Lua compatibility layer, `ip`, `curl`, and `conntrack`.
- The exit router currently needs fw3/iptables, TUN support, Lua 5.1, `ip`, and `curl`.
- Current automatic endpoint discovery uses authenticated peer paths in your own ZeroTier network. Both discovery peers must be authorized, and their identities must be fixed in the configuration.

See [compatibility](COMPATIBILITY.md). Other firewall combinations, architectures, IPv4-only FEC transport, complete prefix changes, and multiple access routers need separate adaptation and acceptance checks. Do not install another firmware's kernel modules merely because a package name matches.

Independent computer access requires shared private-network credentials, an unused virtual address, a matching native EasyTier exit entry, and route configuration. DHCP can allocate the address, and the official program can generate the local instance identifier. Direct access does not require a local OpenWrt router. A reachable public address can provide a direct connection, but the actual peer path must distinguish direct access from relay transport. Public IPv4 behind an upstream router needs the appropriate UDP port mapping; IPv6 access needs a reachable global address on the exit host and matching firewall rules.

This repository does not currently automate or claim acceptance for Linux/NAS exits or the full Windows WireGuard + UDPspeeder path. A WireGuard pairing file is not a native EasyTier client profile. The exit host is also a different role from the final game or application server.

Gateway rules select destination IPv4 addresses and ports. Automatic discovery of every application's servers and destination IPv6 policy routing are not complete features of this version. APNIC allocation records, if used in an independent PC setup, indicate address registration regions rather than application ownership.

## 3. How the router path works

```text
Devices on the local accelerated network
  -> OpenWrt gateway: select traffic by rules
  -> WireGuard
  -> UDPspeeder FEC over global IPv6
  -> EasyTier WireGuard portal on the authorized regional exit
  -> exit broadband
  -> application server

Unselected traffic -> local Internet connection
```

The two FEC endpoints must use matching parameters. Keep existing working identities, wireless networks, IPv6 settings, and application rules when adopting an existing deployment.

The independent computer path uses a separate native entry:

```text
Official EasyTier computer client
  -> matching native exit entry, directly or through a relay
  -> authorized exit Internet connection
  -> application server

Unselected traffic -> computer's local Internet connection
```

## 4. Install the LuCI extension

This installation is for the OpenWrt gateway mode. Read [AGENTS.md](../AGENTS.md) and [deployment instructions](DEPLOY.md) before making network changes. Back up the access and exit routers first. Independent computer setup starts with [Windows notes](WINDOWS-TRAVEL.md) and [the AI handoff prompt](PORTABLE-AI-PROMPT.md).

Install the upstream `luci-app-easytier` and required dependencies. Build the `openwrt/` package using a compatible OpenWrt SDK, or use the source installation procedure for evaluation:

```sh
sh scripts/install.sh --plan
sh scripts/install.sh --install
```

The preview does not include an IPK that is claimed to have completed SDK build acceptance. Review the installation plan. It must not replace your WAN or wireless configuration.

The page extends the existing **VPN → EasyTier** menu. The Chinese entry **跨地区游戏加速** means “Cross-region game acceleration.” It does not start a second web server or replace EasyTier's original management pages.

Legacy internal package, UCI, and file identifiers containing `home-game` remain for upgrade compatibility. The public project name is **EasyTier Cross-Region Game Accelerator**.

## 5. Configure the OpenWrt access and exit gateways

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

## 10. Independent computer access

Install the **official EasyTier GUI** from the [official download page](https://easytier.cn/guide/download.html) to access an authorized regional exit from a computer independently of the local OpenWrt router. Keep its configuration private. Authorized clients may use the same filled profile with DHCP enabled and fixed address/instance fields omitted; the official program allocates an available virtual address and generates the local instance identifier. Do not copy a fixed-address restore profile to several running clients. The exit needs a matching native EasyTier listener, network identity, and Internet forwarding configuration. This mode covers that computer's selected traffic; the gateway mode manages devices using its accelerated network.

An independent native EasyTier client needs its own acceptance checks. It does not automatically include the router's UDPspeeder FEC path. Stop conflicting old services before starting a GUI profile with the same address. Exclude tunnel interfaces and tunnel subnets from the underlay so a tunnel cannot become its own transport.

See [Windows notes](WINDOWS-TRAVEL.md) and [the AI handoff prompt](PORTABLE-AI-PROMPT.md). The public repository does not contain preconfigured access to an owner's exit.

## 11. Public learning resources

[VPN Gate](https://www.vpngate.net/en/) offers a public volunteer VPN project for learning about VPN protocols and connections. **This project does not guarantee its effectiveness, availability, or safety. Use it cautiously.** It is separate from EasyTier, is not configured as a default peer, and is not a guaranteed free exit in the region you need.

See [public resources](PUBLIC-RESOURCES.md). Shared EasyTier relays, Internet exits, and third-party VPN services are different capabilities; permission and actual exit verification still matter.

## 12. Attribution

EasyTier, WireGuard, UDPspeeder, and ZeroTier provide the underlying protocols and algorithms. This project contributes deployment integration, routing management, recovery checks, and LuCI controls. New project code is licensed under Apache-2.0; third-party components retain their own licenses.


## 13. Reuse a working OpenWrt FEC gateway

The official client can add a local native connection to a gateway that already manages a working regional exit:

```text
Official computer client -> native entry on the policy gateway
  -> existing traffic selection -> existing WireGuard + UDPspeeder -> authorized exit
Unselected IPv4 -> gateway's local Internet connection
```

Read [native-gateway integration](NATIVE-GATEWAY.md) and [deployment lessons](DEPLOYMENT-LESSONS.md). The Chinese steps include reference TOML files for EasyTier 2.6.4. Fill matching private credentials, entry addresses and the virtual subnet before importing. A client using DHCP does not need a manually assigned account or address. The gateway keeps a fixed virtual address for its exit role.

Manual gateway integration must cover the new TUN source in the existing classifier, policy routing, forwarding and return path. If the old WireGuard path only admits its existing source, add the appropriate allowed range or source NAT for selected traffic. Preserve local forwarding, DNS/NTP exclusions, underlay bypass and IPv6. The new native interface does not automatically inherit every application-specific TCP/DNS rule.

The TOML field is `routes`, while the CLI option is `--manual-routes`. Two IPv4 `/1` routes can hand traffic to a policy gateway when an equal-prefix default loses on metric. Check underlay reachability first; this is not a universal default for direct native exits. Windows selects the longest matching prefix before comparing metrics. [Microsoft routing reference](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-tcpip-interfaces-interface-routes-route-metric)

Keep rules persistent across firewall reloads and clean up only this entry's changes when stopping. Endpoint discovery remains on the router; it updates authenticated addresses and validates the current exit before restoring selected forwarding. The hotplug hook also matches configured WAN names and ZeroTier `zt*` devices, with polling as a fallback.

Treat parsing, address allocation, real TUN routing, application traffic and recovery as separate checks. A `--check-config` pass or two `--no-tun` instances does not establish another physical computer's exit path. A login TCP request does not establish that a game scene's UDP uses the selected exit. Measure actual connections and keep untested external networks explicit.

## 14. Changing Wi-Fi, hotspots and physical IP addresses

Mobile access should keep the same private profile when the computer changes networks. The user should not need to rewrite the physical IP address, gateway or virtual address. An optional Windows component now maintains owned routes for the official-client -> authorized ZeroTier -> existing native-gateway IPv4 mode. It retains the official GUI. Deploy it explicitly using the linked instructions and validate the actual device; it is not a universal roaming or seamless-session guarantee.

Keep three changes separate: the computer's physical interface/address/gateway, EasyTier's virtual address allocation, and the remote exit's public endpoint. Virtual DHCP and router-side endpoint monitoring do not establish recovery of the computer's underlay. A fixed virtual address does not require a fixed public IP.

Read [network roaming requirements](NETWORK-ROAMING.md). After a switch, transport must use the current physical network, with necessary bypass routes updated and only obsolete routes owned by this project removed. Full IPv4 routes must not send the tunnel's transport back through itself. An unbound interface setting or a working LAN entry is not sufficient evidence. A client using an existing gateway also needs a remotely reachable entry; all required gateways must stay online.

Prefer the official client, official service mode and existing components. Do not create a replacement UI. Where automatic local recovery is requested, inspect and explicitly install the supplied `windows/` background component. It monitors network events, refreshes IPv4 underlay bypasses and gates the two managed `/1` routes on native-gateway and explicit IPv4 HTTPS checks (Windows curl.exe is required). `entry_verified` does not replace regional-exit verification on the router. The current component requires a physical IPv4 gateway; IPv6-only underlays need separate adaptation. If the chosen architecture cannot maintain required routes automatically, report that work as incomplete rather than requiring a fixed hotspot IP.

Test Wi-Fi -> phone hotspot -> original Wi-Fi without changing the profile. Check the current gateway, direct/relayed peer path, TUN, selected exit, ordinary Internet and new application connections. Record recovery time. Report IPv4-only access, DHCP/gateway changes, brief outages and stop/restart separately as passed, failed or not performed. Roaming does not imply seamless preservation of game sessions. Restricted networks may require relays and have different performance. [ZeroTier network guidance](https://docs.zerotier.com/routertips/)


Changing countries does not require a new physical IP in the shared profile. Reachability and latency still depend on the local network and authorized entry. Reusing a policy gateway in another region adds a segment; the Windows recovery component does not automatically select the lowest-latency exit. Direct native access to the regional exit is a separate deployment mode and does not automatically include the gateway's UDP FEC backend.


## Direct exit with the official Windows GUI

The optional direct mode connects the official GUI to a local UDPspeeder, then to the authorized exit's native EasyTier service. It prefers a discovered global IPv6 entry and can fall back to the same exit through an authorized ZeroTier IPv4 path. The original access-side router is not a required transit node. This is native EasyTier plus UDPspeeder, separate from the router's WireGuard backbone.

See [the direct-mode guide](DIRECT-HOME.md) and [the step-by-step manual](../manual/README.md). Install the Windows task explicitly after reviewing the private configuration. A fresh virtual-gateway check and IPv4 HTTPS request bound to the TUN source must pass before selected destination routes are installed. When ICMP is lost, TCP DNS at the virtual gateway and bound HTTPS must both succeed. Total failure removes owned regional routes. Existing foreign traffic and physical IPv6 retain their ordinary paths.

The exit binds each current global IPv6 separately so replies use the correct source address. Both sides monitor relevant address changes, but polling intervals are not recovery-time guarantees. A DHCP template can be shared by authorized computers; do not clone fixed virtual addresses or ZeroTier device identities. Test a different hotspot, ISP prefix changes, a second physical PC and full reboot separately. Do not claim universal reachability or uninterrupted game sessions.


Health checks refresh before successful proof expires. A transient failed probe may retain routes only while previous proof remains fresh, and is reported as degraded. Failures never advance the successful timestamp. Changes to the physical network, virtual address or transport endpoint discard earlier proof. Expiry removes owned regional routes.
