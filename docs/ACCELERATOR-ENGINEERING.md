# 加速项目源码阅读与改进方向

gtun 的多线路探测、TCP/UDP 透明转发和域名分流值得参考。现阶段应保留官方 EasyTier 与已有地区出口，先改善路径质量判断和应用转发范围，再决定是否增加另一种传输协议。

本文是源码和官方文档评估。下述候选功能没有因此部署或验收，也没有新增应用延迟测量。线路质量、出口位置、运营商路径、丢包和排队都影响效果；软件名称不能代替对照测试。

## 1. 阅读范围与证据

- gtun 固定源码：`c16fb72d72c773362aad78bb36e695d9569959c6`。阅读 README、游戏盒文档、客户端 UDP 透明代理、路由选择、线路探测、服务端转发及示例重定向脚本。
- gtun 的 optw 依赖固定源码：`1ff6737f5dc609e11f8b19e85b660f6ab5e02b8c`。按 go.mod 指定版本检查 QUIC、KCP 的 OpenStream 实现，未用默认分支代替固定依赖。
- 其他项目阅读其官方说明或协议文档，范围见对应链接。没有把每个项目的整个代码库都审计一遍。
- “源码事实”指能够从所读实现确认的行为。“推断”指据此判断的潜在影响。“方案”是后续开发、试验和验收的建议。

## 2. gtun：可参考的机制与需要核实的行为

### TCP/UDP 分流与线路选择

gtun 提供透明 TCP/UDP 代理，并用 dnsmasq/ipset 配合域名范围。客户端可配置多个传输入口和探测目标，再按区域选择连接。它需要用户自己的服务端和可用线路，项目本身不附带免费优质出口。[项目说明](https://github.com/ICKelin/gtun)、[游戏盒说明](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/doc/%E7%8E%A9%E8%BD%ACN1%E7%9B%92%E5%AD%90_%E5%9F%BA%E4%BA%8Egtun%E5%AE%9E%E7%8E%B0%E7%9A%84%E6%B8%B8%E6%88%8F%E5%8A%A0%E9%80%9F%E7%9B%92.md)

工程建议：将规则的目的地址来源、协议范围、选中出口和实际命中计数一起记录。规则显示“已保存”不足以说明应用流量经过出口，更不足以说明应用响应变快。

### UDP 被封装到可靠流

源码事实：客户端 UDP 会话调用 `sess.OpenStream()`，按长度封装数据；服务端也从流中读出完整消息后发往 UDP 目的。固定版本 optw 的 QUIC 实现调用 QUIC `OpenStream()`，KCP 实现使用 smux。[客户端 UDP 实现](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/src/gtun/proxy/tproxy_udp.go)、[服务端实现](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/src/gtund/server.go)、[固定 QUIC 依赖](https://github.com/ICKelin/optw/blob/1ff6737f5dc609e11f8b19e85b660f6ab5e02b8c/quic/conn.go)、[固定 KCP 依赖](https://github.com/ICKelin/optw/blob/1ff6737f5dc609e11f8b19e85b660f6ab5e02b8c/kcp/conn.go)

推断：QUIC 流提供有序字节交付。某段数据丢失时，同一流后续的游戏数据可能等待缺失内容重传，增加时效损失。该影响针对同一流，不应描述为所有 QUIC 流都会互相阻塞。这里没有 gtun 游戏实测，不能据此断言它一定更慢。[QUIC 流语义](https://www.rfc-editor.org/rfc/rfc9000.html#section-2)

方案：实时游戏应优先保留数据报语义；如果试验 gtun，单独比较丢包环境中的游戏延迟分位数、断线和恢复时间，不能只测下载速度。

### 探测评分不宜直接照搬

源码事实：探测任务启动后每 120 秒触发，各目标顺序执行 60 次 UDP 测量，读超时为 2 秒。`lossRate` 为 0 到 1 的比例，但分段阈值使用 0.75、1.25、2.25，注释却写百分比。RTT 成功值累加后仍除以 60；有丢包时，这不是成功响应的平均 RTT。[探测代码](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/src/gtun/route/trace.go)

推断：评分可能低估有丢包线路的响应延迟，阈值的单位也需要核对。不可达目标可能拖慢后续目标的测量。上述为代码阅读结果，未作为运行故障复现。

方案：探测器分别保存成功 RTT 样本与丢包率，计算中位数、P95、波动和样本有效期。换网事件触发重新验证；周期探测采用受限并发与总超时。评分必须先排除不可用路径。

### 平台与防火墙

所读透明 UDP 实现使用 Linux IPv4 套接字；示例重定向脚本使用 iptables/ipset、systemctl，并复制 dnsmasq 配置。它们不能直接充当 Windows 官方 GUI 配置，也不能未经适配在现有 OpenWrt fw4 上执行。[UDP 实现](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/src/gtun/proxy/tproxy_udp.go)、[域名重定向脚本](https://github.com/ICKelin/gtun/blob/c16fb72d72c773362aad78bb36e695d9569959c6/scripts/redirect_domains.sh)

方案：可参考设计，但规则应适配实际 fw3/fw4 环境，只管理本项目拥有的链、标记和策略表，保留既有 DNS 与目的 IPv6 行为。

## 3. 其他项目的工程启示

| 项目 | 官方材料确认的机制 | 对本项目的建议 |
| --- | --- | --- |
| [EasyTier](https://easytier.cn/guide/network/configurations.html) | 延迟优先转发、出口节点、TCP 的 KCP/QUIC 代理 | 先核对安装版本和现有拓扑。同一组网中的路径选择，不等于自动切换两套独立 GUI 配置；TCP 代理也不自动改善游戏 UDP。 |
| [sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/)、[URLTest](https://sing-box.sagernet.org/configuration/outbound/urltest/) | Linux nftables/fw4 接入；选路测试容差；是否中断既有连接的选项 | 参考策略引擎、底层绕行和切换容差。启用前检查 mark 冲突与版本，不同时引入竞争默认路由的 TUN。HTTPS 探测不能替代游戏路径测试。 |
| [Hysteria 2](https://v2.hysteria.network/docs/developers/Protocol/) | TCP 使用 QUIC 流；UDP 使用不可靠 QUIC DATAGRAM | 可作为软件 TCP 与游戏 UDP 的独立对照候选。数据报语义值得参考，但不代表在当前线路上一定优于既有方案。 |
| [UDPspeeder](https://github.com/wangyu-/UDPspeeder) | 用额外冗余包恢复丢失；参数可控制冗余与排队 | 用实测选择纠错参数，同时记录外层字节与原始业务字节。已使用 FEC 不代表参数已经最优。 |
| [Glorytun](https://github.com/angt/glorytun) | 多路径、备用路径、整形、路径 MTU 探测；Linux/POSIX 为主要平台 | 参考同一隧道与同一出口下的路径恢复设计。没有在本项目 Windows 客户端完成移植或部署；所读说明不能作为“自适应 FEC”的依据。 |
| [Phantun](https://github.com/dndx/phantun) | UDP 伪装成 TCP 形态，保留乱序等 UDP 属性，用于 UDP 受限环境 | 作为连接受阻时的候选后备。它不提供更短的运营商线路；当前 UDP 可达时应先查路径和排队。 |
| [SQM](https://github.com/tohojo/sqm-scripts)、[cake-autorate](https://github.com/lynxthecat/cake-autorate) | CAKE/fq_codel 控制排队；后者按负载和延迟调整可变链路整形速率 | 适合排查下载、上传时延迟突然升高。需要控制适当接口；家中路由器不能直接控制另一端手机运营商的全部队列。 |

Hysteria 的性能说明也提醒 UDP 缓冲与 CPU 开销。增加协议、纠错与加密层后，应观察路由器和电脑资源，不将更多组件视为默认更快。[官方性能说明](https://v2.hysteria.network/docs/advanced/Performance/)

## 4. 优先改进现有方案

### 第一步：按完整链路判断质量

分别验证直达授权地区出口，以及经已有网关到同一出口。中转入口的低延迟仅说明第一段快。每条候选路径都要检查出口可达、实际业务转发、丢包、RTT 分布和数据新鲜度。

新增质量记录应与已有“可用性证明”分开。现有恢复模块用于撤下失效路线和重建连接，没有因此变成完整路径的自动质量选路器。

### 第二步：把应用需要的协议纳入规则

先核对网关实际分类。已有游戏 UDP 规则不会自动覆盖行情软件的 TCP、HTTPS、DNS 或目的 IPv6。选定应用应检查 DNS、连接建立、TLS、首字节和页面加载各阶段，再选择转发范围。

规则更新考虑域名解析、TTL、A/AAAA 地址、共享 CDN 和设备范围。路由器通常看不到电脑的进程名；DoH、硬编码 IP 和共享地址也会限制应用识别。不能承诺自动发现所有软件服务器。

验收至少包含：存储读回、实际系统规则、设备命中、对应 TCP/UDP 流量、授权出口出网，以及同一页面或场景的前后对照。无需解密用户的 TLS 内容。

### 第三步：为 FEC 设置可量化的预算

按 UDPspeeder 的数据包与冗余包语义，`2:30` 对应每组 2 个数据包和 30 个冗余包，名义发送包数为原数据包的 16 倍。mode、分组、填充和聚合会改变字节比例，不能写成固定 16 倍流量。[参数说明](https://github.com/wangyu-/UDPspeeder)

后续可对照原参数和较低冗余候选。每次仅改变一个因素，两端确认兼容，测业务延迟、损失、外层字节、CPU 和负载下排队。减少冗余可能降低恢复能力；候选值未经测试不能替代现用配置。

自适应策略应先输出建议和证据，再验证在线参数调整接口、切换一致性与回退，不能把参数可调整写成自动优化已经实现。

### 第四步：减少不必要的路径切换

网络地址变动后，刷新实际接口、网关与底层绕行，并重新验证当前出口。质量选路还需要样本有效期、切换容差、冷却期和既有连接处理，防止瞬时抖动导致反复切换。

可先试验连续多个窗口较优才切换的策略，阈值从真实数据选择。出口公网地址或 NAT 状态改变时，游戏可能需要重连。维持同一最终出口、虚拟身份与会话状态是减少中断的方向，尚不能承诺任意网络间零中断。

### 第五步：必要时进行传输对照

如果前四项确认后仍有问题，再在独立范围内比较现用 EasyTier/FEC、EasyTier 的 TCP 代理、Hysteria 或 gtun。候选使用明确且两端一致的名称、独立测试范围和可恢复配置，一次只改变一条路径。

## 5. 验收与记录

| 检查 | 应保存的证据 |
| --- | --- |
| 路径确实可用 | 新鲜的入口与最终出口探测，绑定正确虚拟源的业务证明 |
| 应用经过目标出口 | 规则读回、流量计数、对应协议连接、出口侧核对 |
| 效果改善 | 同一网络和场景的关闭/开启对照，中位数、P95、丢包与断线 |
| 纠错代价可接受 | 原始业务字节、外层字节、CPU、负载下 RTT |
| 换网自动恢复 | 真实 Wi-Fi/热点切换、旧路线清理、重验证与恢复耗时 |
| 失败可恢复 | 撤下自身规则后普通网络可用，保留原配置和失败记录 |

公共资料只保存通用实现、来源和验收方法。实际地址、网络凭据、SSID、个人截图与个人测试记录继续留在私人资料中。配置、原始日志和历史结果只追加说明，不用新的研究结论改写原测试。

相关现有文档：[多路径配置](ROUTE-PROFILES.md)、[换网恢复](NETWORK-ROAMING.md)、[原生网关](NATIVE-GATEWAY.md)、[验收](ACCEPTANCE.md)。
