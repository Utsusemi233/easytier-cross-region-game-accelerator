# 出口端逐地址纠错入口参考

这些文件供管理员按 [出口手册](../manual/01-home/README.md) 审阅安装，不由原网关安装脚本自动部署。先安装匹配架构、来源已核验的二进制，配置独立原生 EasyTier、本机 UDP 入口、互联网转发/NAT 和有名称的防火墙规则。

将已填写的 `direct-fec.env.example` 保存为 `/etc/easytier-direct/fec.env`，配对密钥保存到该文件指定的 KEY_FILE，均设 root 专有权限。PRIVATE_IPV4 必须是自有已授权私网的本机地址；公开文档保留地址不能使用。两端 key、端口、FEC 和模式匹配，示例参数仅展示格式。

- 两份 `.sh` 放到 `/usr/libexec/easytier-direct/`，设可执行。
- `direct-fec.init` 放为 `/etc/init.d/easytier-direct-fec`；另一 init 放为 `/etc/init.d/easytier-direct-fec-endpoints`。
- 先单独启动并检查地址、回包源、虚拟网关和出网，再启用 procd 开机运行与地址监测。

监测每两秒比较 WAN 全球 IPv6；变化时重建自己的逐地址 UDPspeeder 监听。它不配置防火墙/NAT，也不替代电脑的认证发现和新鲜出口验证。首次部署、接口改变、防火墙重载和开机恢复要各自检查。不要把 root 配置目录设为普通用户可写，也不要从不受信任的网络下载并 source 配置。
