# 节点来源与授权

出口来自你自己管理或明确获授权的目标地区网络，可以是家庭宽带，也可以是公网出口主机。出口设备需运行匹配的隧道服务并允许互联网转发；它与最终游戏或应用服务器是不同角色。当前自动部署针对 OpenWrt 出口，Linux 主机或 NAS 的服务与转发需另行部署和验证。

OpenWrt 网关模式的当前 IPv6 直连纠错通道连接固定授权出口。电脑原生 EasyTier 入口使用独立配置，实际可能直连或中继；两种入口均须验证互联网流量确实使用预期出口。

[EasyTier官方共享节点说明](https://easytier.cn/guide/network/host-public-server.html)与[完整参数](https://easytier.cn/guide/network/configurations.html)区分public relay、exit-nodes/enable-exit-node。公共节点可帮助发现/中继虚拟网络，互联网出口需要独立配置和运营者允许。

查阅的[EasyTierGame](https://github.com/EasyTier/EasytierGame)与[EasyTier Manager](https://github.com/EasyTier/easytier-manager)提供组网管理或联机功能；文档中“群友提供服务器”不能证明其节点免费允许所有人代理国内游戏互联网流量。项目不会自动加入他人私有网络、扫描出口或公开所有者的家庭节点信息。

若将来运营者提供公开、明确授权的游戏出口，记录其地域、协议、授权方式、带宽/使用条件、可用期，再在隔离测试规则下验证延迟与出口。当前没有验证过的免费国内互联网出口列表。
