# onekeyeasytier

## 一条命令加入我的网络

适用于 Debian、Ubuntu、Alpine 等 Linux 节点：

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/install-easytier-node.sh | sudo bash
```
适用于 macOS，安装管理脚本后可直接运行 `et`：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/easytier.sh \
  -o /tmp/easytier-manager.sh

sudo mkdir -p /usr/local/libexec
sudo install -m 755 \
  /tmp/easytier-manager.sh \
  /usr/local/libexec/easytier-manager.sh

sudo bash /usr/local/libexec/easytier-manager.sh
```

Linux、Alpine 也可以使用同一个交互式管理器：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/easytier.sh)
```
脚本默认连接自建服务节点 `tcp://tcc.933999.xyz:11010`，加入网络 `hostdzire`，
并通过 EasyTier DHCP 自动获得 `10.126.126.0/24` 网段地址。首次运行会隐藏读取
网络密钥，并保存到权限为 `0600` 的 `/etc/easytier/network.secret`；以后重复运行
同一条命令即可更新或修复节点。网络密钥不限制字符数量，但不能为空，并且所有
节点必须使用完全相同的值。

安装器会完成：

- 自动安装 GitHub Releases 中最新的 EasyTier 稳定版，并校验发布包的官方 SHA256 digest。
- 生成权限为 `0600` 的节点配置，并在启动前执行 `--check-config`。
- 安装 systemd 或 OpenRC 服务，设置开机启动和异常自动重启。
- 幂等放行 `tun0` 上来自 `10.126.126.0/24` 的入站流量，不开放公网接口。
- 等待远端 Peer 上线，并输出节点与 Peer 状态。

不要把网络密钥写入公开仓库、URL 或命令行。当前网络密钥曾在聊天中展示过，
部署前应先在服务端及现有节点统一更换为新的强密钥。

### 可选参数

需要静态虚拟 IP：

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/install-easytier-node.sh | \
  sudo EASYTIER_IPV4=10.126.126.20/24 bash
```

无人值守部署应预先安全放置仅 root 可读的密钥文件：

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/install-easytier-node.sh | \
  sudo EASYTIER_SECRET_FILE=/root/easytier.secret bash
```

其他可覆盖项：`EASYTIER_NETWORK_NAME`、`EASYTIER_PEER`、
`EASYTIER_VERSION`、`EASYTIER_SHA256`、`EASYTIER_LISTEN_PORT`、
`EASYTIER_MTU`、`EASYTIER_TRUST_CIDR`。把
`EASYTIER_TRUST_CIDR` 设置为 `none` 可禁用自动防火墙规则。

## 原有交互式脚本

一键组网，天下无敌。上面有windows版本，复制了在powershell运行就可以

![ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png](https://cdn.nodeimage.com/i/ec9mmBQAWMdMVdkePVvogUYIT4YlodQo.png)
```
bash <(curl -fsSL https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/easytier.sh)
```
- ✨ 这个脚本凭什么被称为“宇宙无敌好用”？
- 🖥️ 全平台制霸
- 完美适配主流系统，并为每个系统提供了最佳实践：
- 
- Linux (Debian/Ubuntu): 使用 Systemd 管理。
- Alpine Linux: 使用 OpenRC + supervise-daemon 实现真·进程守护。
- macOS: 使用 Launchd 实现标准服务管理。
- ✨ 真正的一站式体验
- 从安装到卸载，所有操作集成在一个清爽的交互式菜单中：
- 
- 安装/更新: 自动检测最新版，支持 aarch64 和 x86_64 架构。
- 部署/加入网络: 引导式配置，告别手动编辑 toml 文件的烦恼。
- 服务管理: 轻松实现启动、停止、重启、查看状态、设置/取消开机自启。
- 配置/节点查看: 快速预览当前配置文件和网络节点信息。
- 配置更新: 修改网络名称、网络密钥、静态 IP 或 DHCP，校验通过后自动备份并重启服务。
- 节点名称: 主菜单修改 EasyTier 顶层 `hostname` 字段，自动识别服务实际使用的 `node.toml` 或 `easytier.toml`，重启后验证 Local 节点名称确实生效。
- 脚本更新: 主菜单可从 GitHub 更新管理脚本，语法校验通过后原子替换并保留旧版本备份。
- Peer 节点管理: 可新增、修改或删除指定 Peer 配置；删除整个配置前会二次确认并保留备份。
- 出口节点管理: 可将当前节点设为互联网出口，也可按虚拟 IPv4 选择一个或多个出口并设置故障切换优先级，随时恢复直连。
- 一键卸载: 干净、彻底，不留任何残余。
- 🧠 超乎想象的智能化
- 脚本内置了大量自动化逻辑，让你“只做选择，不干杂活”：
- 
- 自动 IP/DHCP: 在配置节点时，虚拟 IP 地址留空即可自动启用 DHCP，省心省力。
- 默认公共节点: 加入网络时，如果忘记或懒得输入对端节点，脚本会自动使用官方公共节点作为默认值。
- 自动快捷方式: 首次运行时，会自动在 /usr/local/bin 创建 et 命令，之后你可以在任何地方输入 et 快速唤出管理菜单。
- 部署即自启: 在你选择“部署”或“加入”网络后，脚本会自动将服务启动并设置为开机自启，无需任何额外的手动操作！
- 💪 绝对的稳定可靠
- 
- 为不同系统量身打造了最强的进程守护策略 (Restart=always, supervise-daemon, KeepAlive)，确保你的 EasyTier 服务 7x24 小时稳定在线。
- 自动检测 curl, jq 等核心依赖，如果缺失会提示并帮助你自动安装。
- 内置 GitHub 代理选项，有效解决国内服务器下载困难的问题。

## 配置互联网出口

先在具备公网访问能力的节点运行 `et`，进入“管理出口节点”，选择“允许本机作为出口节点”。然后在客户端节点进入同一菜单，选择“选择/切换本机出口”，填写出口节点在 EasyTier 网络中的虚拟 IPv4（例如 `10.126.126.2`）。

可以按顺序填写多个地址，例如 `10.126.126.2, 10.126.126.3`，前面的节点优先，后面的节点用于故障切换。“恢复直连”会清空出口列表。出口切换会改变默认互联网流量路径，远程操作时应保留云厂商控制台或其他恢复通道。

CLI 版 EasyTier 不会仅凭 `exit_nodes` 自动接管系统默认路由。管理脚本会额外写入两条 IPv4 `/1` 路由，并为配置中的 Peer 公网 IPv4 保留物理网关绕行路由，避免 EasyTier 控制连接被导回 TUN。出口模式会暂时启用 `disable_p2p`，使连接固定经过可保护的已配置 Peer；恢复直连时会还原原有的自定义路由和 P2P 设置。

当前全局出口功能覆盖 Linux、Alpine 和 macOS 的 IPv4 流量。它不会接管 IPv6；如需避免 IPv6 继续本地直连，应在系统或 EasyTier 配置中单独禁用 IPv6。出口模式下脚本会阻止修改 Peer；需要调整 Peer 时，先恢复直连，修改完成后再重新选择出口。
