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

- 安装固定版本 EasyTier `v2.6.4`，校验 x86_64、aarch64 或 armv7 发布包 SHA256。
- 生成权限为 `0600` 的节点配置，并在启动前执行 `--check-config`。
- 安装 systemd 或 OpenRC 服务，设置开机启动和异常自动重启。
- 幂等放行 `tun0` 上来自 `10.126.126.0/24` 的入站流量，不开放公网接口。
- 等待远端 Peer 上线，并输出节点与 Peer 状态。
- 每分钟在本机刷新结构化资产清单 `/var/lib/easytier-assets/nodes.json` 和可读清单
  `/var/lib/easytier-assets/NODES.md`，掉线节点会保留并标记为 `offline`。
- 安装 `easytier-fleet-ssh` Codex Skill 和 `et-ssh` 命令，通过节点别名安全连接。

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
`EASYTIER_LISTEN_PORT`、`EASYTIER_MTU`、`EASYTIER_TRUST_CIDR`。把
`EASYTIER_TRUST_CIDR` 设置为 `none` 可禁用自动防火墙规则。

### 本地资产和 Agent SSH

每台服务器都独立从 EasyTier Peer 状态生成本地资产，不需要 GitHub Token：

```bash
et-ssh list
et-ssh refresh
```

SSH 默认使用 `root`、端口 `22` 和机器已有的 SSH Agent/默认私钥。安装时可通过
`EASYTIER_SSH_USER`、`EASYTIER_SSH_PORT`、`EASYTIER_SSH_IDENTITY_FILE` 覆盖。
脚本不会生成、复制或共享私钥。

首次连接前，必须从云控制台或目标机器上的可信会话取得 Ed25519 指纹：

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

在当前节点核对并信任目标：

```bash
et-ssh trust steel-cigarette SHA256:可信指纹
et-ssh connect steel-cigarette
et-ssh exec steel-cigarette 'systemctl --failed'
```

Skill 不会使用 `StrictHostKeyChecking=no`，主机指纹变化时会停止连接。每台机器若都
需要互相 SSH，仍需分别为其现有 SSH 公钥配置目标机器的 `authorized_keys`；资产
发现不会自动分发私钥或修改 SSH 登录策略。

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
- 节点名称: 主菜单提供独立选项修改 EasyTier 显示的 hostname，校验通过后自动重启生效。
- Peer 节点管理: 可新增、修改或删除指定 Peer 配置；删除整个配置前会二次确认并保留备份。
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
