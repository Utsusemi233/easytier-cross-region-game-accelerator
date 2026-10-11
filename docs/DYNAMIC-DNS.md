# IPv6 动态域名与代理连通验证

可选组件为自己管理的 OpenWrt 入口维护 DuckDNS AAAA。它读取指定 Linux 设备上的当前优选全球 IPv6，提交供应商，再核对 DNS。它不提供出口服务，不部署代理，也不修改现有隧道。

## 条件与安装

需有自己的 DuckDNS 子域名和 token、入口主机的全球 IPv6，以及 Lua 5.1、`luci.jsonc`、`nixio`、`ip`、`netstat`、`curl` 和有效 CA 证书。先确认入口绑定地址、上级路由和防火墙允许获授权客户端。不要把出口查询得到的其他设备地址作为入口地址。

备份现有同名文件，填写 `extras/ipv6-relay-ddns/config.example.json`。`interface` 是 `ip -6 addr` 显示的 Linux 设备名，不一定是 UCI 的 `wan6`。`subdomain` 只填已注册的小写标签，不带 `.duckdns.org`。`require_listener=true` 要求指定 TCP 端口监听；UDP-only 入口不适用该监听检查。确实只发布设备地址时可明确设为 `false`，并另外验证实际服务。

从仓库根目录手工安装自己审阅过的文件：

```sh
umask 077
mkdir -p /etc/codex-relay-ddns /usr/libexec/codex-relay-ddns
cp extras/ipv6-relay-ddns/relay-ddns.lua /usr/libexec/codex-relay-ddns/relay-ddns.lua
cp extras/ipv6-relay-ddns/codex-relay-ddns.init /etc/init.d/codex-relay-ddns
cp extras/ipv6-relay-ddns/98-codex-relay-ddns.hotplug /etc/hotplug.d/iface/98-codex-relay-ddns
# 将填写好的私人 JSON 放到 /etc/codex-relay-ddns/config.private.json
chmod 600 /etc/codex-relay-ddns/config.private.json
chmod 755 /etc/init.d/codex-relay-ddns /etc/hotplug.d/iface/98-codex-relay-ddns
/etc/init.d/codex-relay-ddns enable
/etc/init.d/codex-relay-ddns start
lua /usr/libexec/codex-relay-ddns/relay-ddns.lua --status
```

启动后核对 `current_address`、`published_address`、`provider_accepted` 和 `dns_verified`。token 留在权限 600 的路由器配置；请求通过临时 curl 配置文件发送，日志只记录状态名称。DNS 查询会将域名交给配置中采用的公共服务，应在自己授权的范围内使用。

## 频率与恢复范围

| 动作 | 默认间隔 | 是否发送网络请求 |
| --- | --- | --- |
| 读取接口地址、监听与状态 | 10 秒 | 否 |
| 接口事件唤醒 | 最多约 1 秒 | 事件自身只唤醒检测 |
| 已发布记录的 DNS 核对 | 300 秒 | 是，小型 DNS 请求 |
| 地址不变时刷新发布 | 1800 秒 | 是 |
| 发布失败后重试 | 至少 30 秒 | 是 |

地址变化立即清除旧验证状态，发布仍遵守重试限流。供应商接受后尽快核对 DNS，不等待下一次 300 秒定期检查。域名传播、客户端缓存 TTL 与重新建立连接另外耗时；10 秒检测不是 10 秒内恢复所有应用的承诺。服务使用 procd 故障重启，不轮流重启隧道或测速。

AAAA-only 入口应另外检查并处理供应商账号的陈旧 A 记录。本组件不自动删除其他记录。客户端需有 IPv6 可达性；动态域名不能解决没有公网入口、没有 IPv6、端口被封或严重丢包。

## 验证与撤销

```sh
RELAY_DDNS_MODULE=/usr/libexec/codex-relay-ddns/relay-ddns.lua lua extras/ipv6-relay-ddns/check-address-selection.lua
```

检查地址选择和供应商响应解析后，再测试公共 DNS 与真实客户端 HTTPS；UDP 入口要额外测 UDP。状态中的 `proxy_connectivity=NOT_CHECKED_BY_DDNS` 是刻意区分两层结果。DNS 成功不能记作代理成功。

分别记录服务故障重启、接口事件、实际运营商换前缀、整机重启、客户端换网和应用行为。未执行项目保留为未测试。停止此模块时仅停用自身 init/hotplug 文件，按备份恢复自身文件；不要清空其他 DDNS、防火墙或代理规则。

参考：[DuckDNS API](https://www.duckdns.org/spec.jsp)、[Google 公共 DNS DoH](https://developers.google.com/speed/public-dns/docs/doh)。
