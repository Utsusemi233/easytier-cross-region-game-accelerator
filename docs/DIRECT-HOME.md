# 官方 Windows 客户端直连授权出口

这条路径让电脑通过官方 EasyTier GUI 连接授权的地区出口。公网 IPv6 可用时，电脑与出口各运行一端 UDPspeeder，再由出口的原生 EasyTier 接收和转发。公网 IPv6 入口不可用时，维护组件尝试该出口的授权 ZeroTier 虚拟 IPv4 入口。两条路径都以同一台授权设备作为互联网出口，不要求经过原来的访问端 OpenWrt。

它与既有路由器的 WireGuard + UDPspeeder 路径分开。电脑这里是 **EasyTier 原生 UDP + UDPspeeder**，没有在 Windows 上复制原 WireGuard 结构，也不替换官方 GUI。现有 LuCI 插件和旧网关配置继续按各自文档管理。

## 必要条件

Windows 需要管理员权限、官方 GUI 2.6.4、已校验的 Windows UDPspeeder V2，以及加入自有网络并获得授权的 ZeroTier。出口需有匹配的原生 EasyTier、纠错入口、虚拟网卡、互联网转发/NAT和诊断 DNS。先核对固件架构、TUN、防火墙版本、动态库与内存，不能只凭同名软件推断兼容。

Windows 纠错程序来自 [UDPspeeder 官方发布](https://github.com/wangyu-/UDPspeeder/releases/tag/20180806.0)。这里使用其 Windows 发布接口，不把第三方包装程序当官方 GUI。密钥由部署者私下生成与配对，不放入公共示例。

## 分步操作

完整步骤按目录保存于 [manual/](../manual/README.md)。先部署并验证出口，再填写 [Windows 示例](../windows/direct-home.example.json) 和[客户端 TOML](../examples/direct-home-client.toml)。示例中的文档保留地址和占位符不能直接用于公网。

1. 出口加载[原生入口模板](../examples/direct-home-exit.toml)，启用加密、受授权身份和系统转发。出口发布 `0.0.0.0/0` 表示能代为出网；电脑选哪些目的地址是另一项设置。
2. 将出口的 UDPspeeder 送往原生 EasyTier 的本机 UDP 入口。公网端**逐个绑定当前全球 IPv6 地址**，不要依赖通配监听器自动选回包源地址。另保留只在授权私网可达的 IPv4 入口。地址签名变化时重建这些监听器，原生内核和既有其他线路无需一起重启。
3. 核对虚拟网卡到实际 WAN 的转发、源 NAT、TCP MSS及诊断 ICMP/DNS。防火墙规则要持久化，重载和开机后再次核对。
4. 在官方 GUI 导入已填私密身份的客户端 TOML，保存并运行。新设备共用 `dhcp=true` 模板，由官方程序选择未冲突地址；不复制原本机固定地址或 ZeroTier 私钥。
5. 在 `prefixes_file` 填入要通过该出口的 IPv4 CIDR 数组。地区 IP 集合可减少逐个追游戏服务器的需要，但它不是进程识别器，也不能覆盖地区外的 CDN、所有域名或 IPv6 流量。
6. 把 `windows/` 中恢复脚本放在同一目录，先运行安装预览，再显式安装：

```powershell
.\Install-DirectHomeRecovery.ps1 -ConfigPath E:\RegionTravel\private\direct-recovery.json
.\Install-DirectHomeRecovery.ps1 -ConfigPath E:\RegionTravel\private\direct-recovery.json -Apply
```

配置必须指向已下载、已核对摘要的二进制。两端 FEC、密钥、端口和模式必须匹配。示例 `2:4` 是参数格式演示，没有声称是已验证的最佳设置；高冗余 `2:30` 的理论包数量约为原数据的 16 倍，实际带宽还受分组、报文大小和头部影响，应做计数对照。

## 恢复和验证门控

后台组件检查实际物理接口、地址和默认网关，维护有归属记录的 IPv4 底层绕行。它只从配置的家庭 ZeroTier 节点读取活跃、未过期且近期接收过数据的全球 IPv6 路径。已经通过认证并有新鲜出口验证的在用路径，不因发现器短暂省略它而立即换线。

本机地址、网关或虚拟地址变化时，先撤下受管理的地区路线，重建自己的 UDPspeeder。家庭端监测 WAN 全球地址并更新逐地址监听；Windows 再发现、连接与验证。公网入口尝试失败后可走授权私网。检测轮询间隔不是总恢复时间，连接超时、地址传播与应用重连都会增加等待。

虚拟网关通过 ICMP，或通过家庭 DNS/TCP 与绑定源 HTTPS 联合检查；还须有新鲜的**指定虚拟源地址的 IPv4 HTTPS**成功，才启用地区路线。检测站地址可通过家庭 DNS 刷新，并校验 HTTPS 证书；物理 IPv6 能打开网页不能代替此项验证。验证失败或过期则撤下自身地区路线，其他目的地址继续使用原网络。状态文件记录实际检查时间、承载路径和错误，不把界面“运行中”作为完成证据。

`reconnect_app_executables` 可显式列出需要处理的游戏完整路径。线路恢复后，只尝试重建这些程序中仍使用旧源地址、且目的路线当前属于隧道的 IPv4 TCP 连接。它不关闭其他程序的连接，不保证 UDP 会话或全部游戏无缝保持。

## 验收与限制

按 [manual/05-tests/](../manual/05-tests/README.md) 实测同配置换网、真实入口中断、私网回落、回到公网路径、官方 GUI 停用/启动、海外网络和游戏场景。保留每项通过、失败与未执行的记录。重启任务不是整机重启；当前地址别名切换不是运营商真实换前缀；两个无 TUN 实例不是第二台实体电脑验收。

Windows PowerShell 5.1和官方 2.6.4 是本组件的参考范围。IPv6-only 底层有路径处理代码，仍须单独验收；酒店认证页、完全封锁相关承载的网络和多 VPN 不保证可用。共享中继不是公共互联网出口，出口离线时仍需恢复当地连接。电脑所在国家不写死，但不同线路的延迟和可达性必须实测。

停用时在官方 GUI 点击禁用网络。移除恢复组件用安装脚本的 `-Remove`，仅撤销本次部署明确拥有的任务、进程和路线；见 [manual/06-restore/](../manual/06-restore/README.md)。


健康验证会在有效期到期前尝试刷新。单次超时只在已有成功证明尚未过期时保留路线，状态显示降级；失败不能刷新成功时间。物理网络、虚拟地址或端点改变时清空旧证明。超过有效期仍未通过，就撤下项目地区路线，避免短探测抖动与过期假成功两种问题。
