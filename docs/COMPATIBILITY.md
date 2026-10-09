# 兼容性与部署范围

以下为脚本针对的接口和参考版本，不是对所有设备的硬件验收承诺。

| 角色 | 脚本目标 | 部署要求 |
| --- | --- | --- |
| 访问端 | OpenWrt 衍生固件，fw4/nftables | Lua5.1、LuCI Lua兼容层、WireGuard内核、ip、curl、conntrack |
| 授权出口端 | OpenWrt 衍生固件，fw3/iptables | Lua5.1、TUN、iptables、ip、curl |
| EasyTier | core 2.4.5 参考接口；LuCI 2.6.4 参考代码 | 同时核对 core 与界面版本，不以版本号推断全部参数兼容 |
| UDPspeeder | V2 参考接口 | 匹配 CPU 架构，两端参数一致 |
| 其他架构、客户端fw3、出口fw4 | 需要另行适配 | 部署条件检查未通过时停止，不强装别的固件内核包 |
| 纯IPv4、运营商整体换前缀、多访问端 | 需要独立验证 | 不从局部连通推断长期可用 |

上游 LuCI 参考提交：EasyTier/luci-app-easytier `79b2b01ded627a634e4bea8d60c7be0f00b708b0`。当前扩展保留 Lua 控制器与 ES5 页面，不引入额外网页服务。

使用安装脚本清理本扩展自己的 Lua 编译缓存。不同主题、nftables 表达形式、系统库及防火墙版本须在实际设备检查。内存不足时不要叠加新的重型服务。

每次部署都应按[验收方法](ACCEPTANCE.md)记录通过、失败与未执行项目。公开仓库不收录所有者的具体硬件记录、地址或私人测试数据。
