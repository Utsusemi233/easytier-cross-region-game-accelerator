# Clash 复用已有 OpenWrt 纠错网关

Mihomo/Clash 可通过获授权的 Shadowsocks TCP+UDP 入口接入现有 OpenWrt 网关，再复用它的 WireGuard + UDPspeeder 线路。电脑更换接入协议，路由器间的纠错、端点更新与出口 NAT 留在原后端。

```text
电脑 Mihomo TUN → 授权 SS TCP+UDP 入口 → 原 WG/UDPspeeder → 地区出口
                 未选定流量继续使用电脑当地出口
```

这是一条可选手工接入路径。主安装脚本不会部署 SS 入口、授权设备或 Clash 配置。独立 SS 公网出口也不会因为写了 `udp: true` 自动获得 FEC。

## 从实际服务配置生成

读取入口的地址、端口、密码、cipher、UDP 模式和源地址绑定，再核对策略表、WG allowed-ips、NAT、转发和防火墙。不能把 EasyTier TOML 改成 YAML 就称为转换；两个协议需要各自的入口。

[配置模板](../examples/clash-policy-gateway.example.yaml)使用文档地址，没有真实节点或地区地址库。填入自己授权的入口与目标规则后，先用实际核心 `-t -f` 检查，再验证转发。本路径使用标准 SS；不依赖较新 Mihomo 的 `type: easytier`。核心版本支持某种协议字段，也不代表该协议的 TCP/UDP 已验收。

为游戏启用 TUN 或明确的 UDP 转发；浏览器系统代理不覆盖所有 UDP 游戏。采用 Rule 模式，保留未选流量 DIRECT。域名规则、目的地址和实际游戏进程应按平台核对，避免强制所有流量跨境。

## 动态接入

可使用自己管理的认证私网固定虚拟地址作为网关入口。底层网络更换后，私网软件负责恢复物理路径；客户端文件不写当前物理 IP。不要固定绑定 WLAN、热点 IPv4 或某次物理网关。需要绑定时只绑定真实存在的授权虚拟接口，并确保底层软件流量 DIRECT，避免回环。

每台设备加入自己的已授权身份，入口按实际设备授权。不要克隆 ZeroTier identity、WireGuard 密钥或硬编码地址。私网没有 DHCP 加入和服务授权时，复制 YAML 本身不够。

另一条路径是在可达公网入口上使用动态域名，见 [DYNAMIC-DNS.md](DYNAMIC-DNS.md)。私网物理路径恢复、远端 IPv6 的 WG/FEC 更新与域名更新是三项不同能力，应分别验收。网络阻断、运营商绕路或没有可达入口时，配置无法保证全球可用或会话无中断。

## 两类常见失败

多网卡网关上，客户端访问另一个子网的地址时，TCP 可以成功而 UDP 回复使用入站接口地址。抓包核对 SS UDP 回复的源地址与客户端配置地址是否一致。使用入站网络对应的地址，或逐地址绑定服务；不要让仅检查 TCP 的 LAN 节点选择把这个问题隐藏。

Windows TUN 若报 `set ipv6 options: The parameter is incorrect`，检查核心日志与虚拟接口。参考模板只为 TUN 分配 IPv4，`inet6-address: []`，同时保留物理网络 IPv6。不要为了一个虚拟接口错误关闭整机 IPv6。此设置应在实际核心版本验证，不是所有 Windows 系统都需要的修复。

## 状态、延迟和回退

使用同一目标比较官方客户端与 Clash：记录样本数、丢包、p50/p95、实际出口与路径。节点 HTTP 探测不是游戏延迟。再完成真实 TUN、游戏登录和场景，最后切换到不同热点并返回原网络。

`fallback` 组的 HTTPS 探测可以在节点不通后为**新连接**选择 DIRECT。它不检测所有 UDP 故障，不证明应用服务可用，也不能迁移旧游戏会话。恢复所需时间还包括探测间隔和重连。先做故障注入对照，再把自动回退列为已验收。

原纠错参数由网关控制，不塞入 Clash YAML；UDP-over-TCP 不等于 FEC。高冗余会增加带宽，不能直接作为所有线路的默认。保留原可用参数后再单项对照，避免同时改协议、MTU 和 FEC 导致无法判断原因。

停止客户端时检查其 TUN/路线释放。撤销服务只清理新增的设备授权和自身文件，不删除其他用户入口或原后端。记录通过、失败、未测试；公开反馈去除私人地址、身份、密钥和个人测速数据。

上游参考：[SS 参数](https://wiki.metacubex.one/config/proxies/ss/)、[TUN 参数](https://wiki.metacubex.one/config/inbound/tun/)、[Fallback 组](https://wiki.metacubex.one/config/proxy-groups/fallback/)。
