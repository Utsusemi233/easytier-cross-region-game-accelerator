# 官方电脑客户端

使用官方 EasyTier GUI，保留原界面和直接打开官方 exe 的快捷方式。将本项目脚本与经过核验的 UDPspeeder 放在独立目录，避免与其他 VPN 或旧恢复任务同时管理同一 TUN。

1. 读取 `docs/DIRECT-HOME.md` 和 `windows/direct-home.example.json`，从自己的私人配对资料填写配置。公开占位符不能直接部署。
2. 在官方编辑器导入已填好的 `examples/direct-home-client.toml`。多台获授权设备可共用网络凭据与 `dhcp=true` 模板；不复制固定 IPv4、`instance_id` 或 ZeroTier 私钥。
3. 客户端 peer 是本机 UDPspeeder 入口，exit 是真实授权出口虚拟地址。GUI 只配置 overlay 网段；地区路线由验证后的维护组件管理，避免两处重复写全局路由。
4. 本机 ZeroTier 加入自有网络并获得授权；配置固定授权家庭节点 ID 和它的私网地址。公网地址由认证的发现路径取得，不能从任意陌生节点取入口。
5. 安装前运行 `Install-DirectHomeRecovery.ps1 -ConfigPath <私人配置>` 查看计划，检查路径、二进制摘要和目标范围。明确部署后以管理员运行同命令加 `-Apply`。
6. 核对官方 GUI 的实际配置、真实 TUN、动态地址、任务状态、新鲜验证与路由。新电脑须单独测试真实应用，不以模板解析替代验收。

日常启动官方 GUI 并运行该配置即可。后台任务不提供第二个客户端界面。停用与彻底移除见下一阶段的恢复文档。

[返回目录](../README.md) · [直连说明](../../docs/DIRECT-HOME.md)


## 分别保存多条路径

先禁用当前官方网络，再启动另一配置；使用不同 TUN 名称。网络名称是配对参数，须与对应入口同步，不能只改单端。保留原直连，新增网关选定路由组件的步骤见 [多路径配置说明](../../docs/ROUTE-PROFILES.md)。
