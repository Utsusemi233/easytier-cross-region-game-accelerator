# DNS 缓存、活动资源与网络切换

游戏能进入场景，网页活动仍可能打不开。活动页面通常要连接另外的脚本、图片、SDK 和登录服务。入口返回 HTTP 200 只说明这一次入口请求成功；大脚本下载不完整、SDK 超时或业务登录失败仍需要分别检查。

## 哪些变化会自动处理

| 情况 | 现有处理方式 | 仍需核对的内容 |
| --- | --- | --- |
| 切换网络后仍使用 Windows 的旧 DNS 缓存 | 可选的 Network-SwitchGuard 在网络变化稳定后清理缓存 | 应用自己的缓存和既有连接可能需要重开窗口或重新连接 |
| 已列入域名规则的服务更换 IPv4 | 所用 DNS 服务重新解析；配置好的 DNS 地址集合随解析更新 | 解析经哪条出口、集合与实际分类是否匹配，取决于该部署的 DNS/防火墙集成 |
| 活动新增域名或迁移到新的服务 | 先诊断，再补充自己的服务域名列表 | 本项目不会自动判定未知域名该走哪个地区 |
| 某个 CDN 地址在当前路径失效 | 比较当前解析、授权出口解析，以及完整 HTTPS 请求 | 清缓存不会把不可达地址变成可达地址，换出口也未必解决失效 CDN |

发布到 GitHub 与运行中的规则更新是两件事。当前组件没有自动从 GitHub 下载或安装脚本，也没有把路由器规则自动下发到所有电脑。代码、配置、任务是否已加载，需在每台设备检查。

## Windows 自动清理缓存

[Network-SwitchGuard.ps1](../windows/Network-SwitchGuard.ps1) 是可选后台组件。它观察活动物理网络的名称、地址、网关、DNS、IPv6 前缀和配置中归属本项目的 TUN。状态文件中的出口证明必须新鲜、地址相符且存在所选路线，才把该配置记为已启用。它不负责创建或修复隧道。

默认示例每次观察后等待 1 秒，变化稳定 3 秒后清理一次 Windows DNS 缓存。断网后重连同一网络也清理；持续不变的网络不反复清理。临时 IPv6 接口标识的轮换不等于前缀变化。状态和有界事件记录保存在配置指定的私有目录。

它不修改 DNS 服务器、代理、官方 TOML 或路线，不关闭游戏或浏览器，也不自动识别活动域名。使用 TUN 状态时，先安装对应的 [直连](DIRECT-HOME.md) 或 [原生网关](ROUTE-PROFILES.md) 路线维护组件。仅使用路由器加速网络时，`profiles` 可以设为 `[]`，只观察物理网络变化。

1. 将两个 NetworkSwitchGuard 脚本放在同一稳定目录，按 [示例配置](../windows/network-switch-guard.example.json) 私下填写路径。
2. `alias` 必须对应实际 TUN，`status_file` 必须对应本项目已有维护任务。不要引用其他 VPN 的状态文件。`proof_ttl_seconds` 与对应出口验证的有效期一致。
3. 先在普通终端检查计划，再在管理员终端明确安装：

```powershell
.\Install-NetworkSwitchGuard.ps1 -ConfigPath E:\RegionTravel\private\dns-switch.private.json
.\Install-NetworkSwitchGuard.ps1 -ConfigPath E:\RegionTravel\private\dns-switch.private.json -Apply
Get-Content E:\RegionTravel\private\dns-switch-state\status.private.json
```

任务名称为 `EasyTier Network Switch DNS Guard`，使用 SYSTEM，开机与登录触发，隐藏运行。重复实例受到限制。卸载使用同一安装脚本和配置路径的 `-Remove`，只移除这项任务。原客户端、路线维护和 DNS 配置保留。

隔离测试执行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\windows-network-switch-guard.ps1`。实际设备仍须检查断线重连、另一网络、客户端开关、普通 HTTPS，以及需要使用的活动页面。应用账号登录与开机恢复分别验收，不用脚本测试代替。

## 新域名的排查与维护

先记录失败页面和具体阶段。查看浏览器失败请求或应用日志时，只取必要的域名、资源路径和错误类型，避免收集账号、Cookie、令牌和请求正文。对静态文件，检查下载是否完整；对登录 API，HTTP 成功不能代替业务成功。

在 Windows 可用下面的形式检查自己选择的公开资源：

```powershell
$domain = 'activity.example.com'
$url = 'https://activity.example.com/assets/main.js'
Resolve-DnsName $domain -Type A
Resolve-DnsName $domain -Type AAAA
curl.exe --noproxy '*' --connect-timeout 5 --max-time 20 -sS -o NUL -w 'http=%{http_code} ip=%{remote_ip} bytes=%{size_download} total=%{time_total}' $url
```

比较当前 DNS 与授权出口的 DNS，再用保留域名和 TLS 证书校验的 `curl --resolve` 检查候选地址。确认出口比较使用指定虚拟源地址，不能将物理网络的成功误算作隧道成功。IPv4 和 IPv6 分别测试，避免因一个域名的失败关闭整个网络的 IPv6。

如果现有 OpenWrt 部署已集成 SmartDNS 与 nft 地址集合，可把已确认的必要域名加入自己的列表，使后续地址变化继续由解析更新。备份列表，检查匹配范围，重新加载对应 DNS 服务，并核对实际返回、地址集合、分类计数和完整页面。某些 CDN IP 被多个服务共用，按 IP 分类的影响可能超出一个域名。需要保留来源接口、地区集合和既有出口健康门控。

主安装器不自动安装这项 SmartDNS 域名集成。现有 LuCI 自定义规则管理来源、目的 CIDR、协议与端口，也不等于具备任意域名的自动诊断。不同部署应按实际已有 DNS 链调整；不要默认接管全部应用 TCP，也不要将 CDN 地址写入永久 hosts 文件。
