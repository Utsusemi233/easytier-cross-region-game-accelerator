# 交给另一台电脑的AI

下面的提示词不包含家庭密钥。使用者须另外通过私人文件或可信渠道提供连接资料，不要上传到公共仓库或直接贴进公共Issue。

```text
请阅读 https://github.com/Utsusemi233/easytier-cross-region-game-accelerator 的AGENTS.md、README.md、docs/WINDOWS-TRAVEL.md和兼容性说明，在这台Windows电脑的E盘目录安装并配置EasyTier，让我无需手填网络设置，并连接到我已有的国内家庭出口。不要重做已经运行的两端OpenWrt部署，不影响现有家庭游戏线路。

我会私下提供家庭原生EasyTier连接资料（网络名称、network_secret、家庭虚拟IPv4、可用入口及共享发现节点），或让你从我授权的已配置电脑读取。路由器的WireGuard配对JSON不能直接当作EasyTier原生配置。

请先检查本机系统/架构、管理员权限、已有VPN、网卡、路由及服务，从官网选择与家庭端兼容的官方 EasyTier GUI 发布版并校验官方 SHA-256。在 E 盘的独立目录安装，把桌面快捷方式直接指向官方 easytier-gui.exe，通过官方界面导入和保存私人配置。不要制作自定义连接界面、替代程序或连接脚本快捷方式。

为新电脑生成独立instance_id、hostname，确认并分配未占用的虚拟IPv4；不要照搬另一台电脑的地址、instance_id或WireGuard私钥。不要自行新建与家庭端不一致的network_name/network_secret。

配置家庭exit node和国内IPv4分流；如使用APNIC中国地址记录，说明它不等于应用自动识别。保留海外流量、原DNS、原IPv6和其他VPN。先用少量真实目标验证，再启用完整范围。不得仅凭进程或“已连接”认定成功。

在必要的Windows管理员确认后自动完成配置，用官方客户端的运行、停止和托盘入口操作；如启用开机恢复，使用官方服务模式并验证。记录修改前后配置并准备仅撤销自身更改的恢复方式。不要未经检查修改家庭端原有服务、无线、纠错参数或系统默认路由。

验证家庭peer可见、实际TUN路由、绑定隧道的HTTPS、家庭公网IPv4出口、普通海外网站、停止后路由释放和再启动恢复。能实测换网络时再验证地址变化；没有热点/酒店或IPv4-only条件时写未测试。原生EasyTier不含UDPspeeder纠错，不承诺达到路由器案例的游戏延迟。

完成后告诉我安装路径、日常连接方法、通过/失败/未测试项目，以及本机恢复方法。密钥和私人连接资料禁止写入GitHub、公开报告或诊断截图。
```
