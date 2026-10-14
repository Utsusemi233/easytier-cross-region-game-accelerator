# Clash 核心内的 UDP 纠错实验

这一扩展让 Windows Clash GUI 使用自编 Mihomo，把 EasyTier 的外层 UDP 送入兼容 UDPspeeder V2 mode-0 的纠错通道。客户端不另起 UDPspeeder 进程。出口仍需要真实的 UDPspeeder 服务、匹配的原生 EasyTier 身份、转发与 NAT；导入 YAML 本身不会创建服务器。

它是实验性核心补丁，不是官方 Mihomo、EasyTier 或 Clash Verge 功能。上游固定为 Mihomo v1.19.32，提交 88dcbf7f1614a67c3b36b848ee3592dfa92ada36。仓库只提供补丁、新增文件和构建入口，完整上游源码由构建时取得。

[English instructions](README.en.md)。

## 范围与当前状态

- 已完成编译、已知 Reed-Solomon 向量、只收到校验片的恢复、校验错误、关闭/超时和 DNS 定向刷新测试。
- 已与原生 UDPspeeder V2 做实际互通，完整 Mihomo 路径能取得授权出口的 TCP 和 UDP 出口。
- 连续、静默和重开测试仍出现个别 UDP 超时，完整稳定性验收尚未全部通过。不能把解析、进程在线或一次出口成功写成游戏延迟保证。
- 这版构建面向 Windows amd64。Android、Shadowrocket、其他架构和原版核心不接受这项扩展。Linux/macOS 接口签名参考实现没有经过换网验收。

## 构建与安装

准备 Git、与固定源码兼容的 Go；本轮构建使用 Go 1.27.2、CGO_ENABLED=0、GOAMD64=v1 和 with_gvisor。执行 Build-MihomoFEC.ps1，可指定 -WorkDir 与 -Go。脚本核对固定提交、补丁是否匹配、目标测试与构建退出码，不删除已有工作目录。版本、源码文件哈希见 source-metadata.json。

保留官方核心、当前订阅和设置备份。以 Clash Verge 的候选核心槽位为例，先把产物放为 verge-mihomo-alpha.exe，再正常登记到服务、选择候选槽位，核对 /version 返回 v1.19.32-fec.4。Clash Verge 2.5.8 服务运行的是管理员登记的副本，只替换 GUI 旁边的文件不会更新该副本。通过上游安装工具的 --prepare-install --core-only --core 接口登记，需要平台管理员确认；不要改服务保护目录或绕过受信路径检查。正式核心和旧配置作为回退入口。

导入 example.yaml 并填写自己的授权配置。节点必须写 type: easytier-fec；普通核心会明确拒绝，避免忽略扩展字段后悄悄按原通道连接。游戏 UDP 需要 Clash 自身 TUN 或应用本来支持代理；系统 HTTP 代理不能自动接管全部游戏 UDP。

## 动态恢复

直连入口写动态域名，不固定电脑物理 IP、网卡名称或虚拟实例地址；dhcp: true 自动取得虚拟 IPv4，本地 instance_id 保存在各自 state-dir。不要把已有机器整个状态目录复制给另一台机器。

Windows 在运行时选择有有效地址和网关的物理 Ethernet、Wi-Fi 或 WWAN，排除 TUN、ZeroTier 和其他虚拟接口。IPv6 入口要求当前物理接口具有可用 IPv6；按该地址族的接口度量选择，不把安装时的 WLAN 名称写入配置。已做虚拟接口排除测试和物理网卡别名更改、恢复的现场对照。多物理接口、陌生热点和运营商整体换前缀仍需分别验收。

FEC 节点每五秒读取物理接口地址/网关签名；改变需要两次稳定观察。配置的入口域名每十五秒查询一次新答案，候选变化在下一次五秒观察确认。刷新只更新入口域名的缓存，不清空应用 DNS；仅重建该节点的 EasyTier 实例，保留状态目录，其他代理不重启。五秒和十五秒是检测间隔，不是完整恢复时间保证；DNS 提供方延迟、受限网络和应用重连仍会增加等待。

重建及 peer_removed 时关闭该节点旧实例的应用 UDP socket，让 Clash 释放对应 NAT 会话；并拒绝在重建并发窗口完成的旧代 socket。关闭阻塞读取、旧代拒绝和新代通信已有测试。受控长 TTL DNS 从失效入口切到有效入口已恢复实际出口并保留身份，但这不是运营商真实换前缀或游戏无缝恢复的证明。API 的 physical-interface 和 recovery-generation 用于核对运行选择及旧会话释放，统计不含认证密钥。

出口侧必须保留逐地址绑定维护及 DDNS 更新，检查新地址确实在网卡上、对应端口正在监听，再验证真实出口。WAN6 控制面登记了地址但内核地址列表缺失时，要分别检查，不能只按服务进程或 DHCP 状态判断公网入口可用。地址重新出现、DNS更新、客户端重建和游戏恢复分别记录。

### 运行中但没有可用路由

`fec.4` 增加数据路径恢复。EasyTier 实例仍显示运行中，但 TCP 或应用 UDP 持续返回 `ENETUNREACH` / `ENETRESET` 时，继续重拨底层连接可能无法恢复业务。核心记录这些明确的路由错误：至少两次错误、持续十秒以上，并且当前实例已启动三十秒后，下一次五秒检查会重建该节点。有效 TCP 连接或实际 UDP 返回会取消待恢复状态。普通目标超时、拒绝连接、调用者取消与旧实例错误不触发重建，不增加外部探测服务。

恢复沿用本地身份并释放旧 UDP 映射。API 新增 `path-route-failures`、`path-restarts`、`last-restart-reason`，用于区分旧 socket 清理和实际节点重建。门槛限制重建频率，不保证恢复用时；出口本身断网时仍需等它恢复。隔离测试覆盖入口地址不变、链路中断后恢复及身份保留；真实游戏断线和不同热点仍需分别验收。

## 参数与代价

示例的 2:30、组包 1ms、分散 5ms 是高冗余实验参数。两个数据片加三十校验片，片数为原数据的十六倍；短包优化可能用一个数据片加三十校验片，开销更高。真实字节比例还含头部、填充与组包，查看 /proxies/节点名 的 udp-fec.stats 的实际发送字节、负载数和恢复片数。不能把它当成所有线路的默认最优值，尤其不要直接用于大流量下载或媒体。

示例只把指定游戏进程的 UDP 交给 FEC。TCP 登录、更新下载和应用 DNS 使用独立的普通路线；如果当地直连不能登录，应填写自己的授权 TCP 代理规则。需要中转处理登录时，不把整个游戏的所有请求描述为直连。已经出现过将大流量 TCP 资源一并送入高冗余路径后更新失败的情况，必须单独验证。

纠错只覆盖显式列出的 FEC 目的端口，不包装 DNS/STUN 等其他 UDP；内部 EasyTier 认证和加密保留。对照时只改一个参数，并保存失败轮次。节点测试 URL、网关 nonce 回显、外部 STUN 与游戏内 RTT 测的是不同范围。

自动候选仅包含代理节点，DIRECT 留在外层 select 组供手动选择。fallback 的第一节点健康时优先使用它，但切換既有 UDP 会话仍需应用重连。实际游戏连接的 chains、双向字节增长、出口端转发/NAT及场景 RTT共同作为验收依据。

上游依据：[Mihomo 固定版本源码](https://github.com/MetaCubeX/mihomo/tree/v1.19.32)、[UDPspeeder V2](https://github.com/wangyu-/UDPspeeder)、[Clash Verge 2.5.8 服务登记](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.8/src-tauri/src/core/service.rs)。许可见 LICENSE.MIHOMO 和 overlay/component/udpspeeder/NOTICE.md。
