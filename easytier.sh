#!/bin/bash

# --- 脚本配置 ---
GITHUB_PROXY="ghfast.top"

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- 平台无关路径和文件名 ---
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/easytier"
DEFAULT_CONFIG_FILE="${CONFIG_DIR}/easytier.toml"
NODE_CONFIG_FILE="${CONFIG_DIR}/node.toml"
CONFIG_FILE="${EASYTIER_CONFIG_FILE:-${DEFAULT_CONFIG_FILE}}"
CORE_BINARY_NAME="easytier-core"
CLI_BINARY_NAME="easytier-cli"
ALIAS_PATH="/usr/local/bin/et"
MANAGER_INSTALL_DIR="${EASYTIER_MANAGER_INSTALL_DIR:-/usr/local/libexec}"
MANAGER_INSTALL_PATH="${MANAGER_INSTALL_DIR}/easytier-manager.sh"
MANAGER_SOURCE_URL="${EASYTIER_MANAGER_SOURCE_URL:-https://raw.githubusercontent.com/shuguangnet/onekeyeasytier/main/easytier.sh}"

# --- 平台特定变量 (将在 main 函数中设置) ---
OS_TYPE=""
SERVICE_FILE=""
SERVICE_LABEL="com.easytier.core"
SERVICE_NAME="easytier"
LOG_FILE="/var/log/easytier.log"

# 原始下载地址
GITHUB_API_URL="https://api.github.com/repos/EasyTier/EasyTier/releases/latest"

# --- 辅助函数 ---
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo -e "${RED}错误: 此脚本必须以 root 或 sudo 权限运行。${NC}"; exit 1
	fi
}

check_dependencies() {
	local missing_deps=()
	for cmd in curl jq unzip; do
		if ! command -v "$cmd" &> /dev/null; then missing_deps+=("$cmd"); fi
	done
	if [ ${#missing_deps[@]} -gt 0 ]; then
		echo -e "${YELLOW}检测到缺失的依赖: ${missing_deps[*]}${NC}"
		if [[ "$OS_TYPE" == "linux" || "$OS_TYPE" == "alpine"  ]]; then
			read -p "是否尝试自动安装? (y/n): " choice
			if [[ "$choice" != "y" && "$choice" != "Y" ]]; then echo -e "${RED}操作中止。${NC}"; exit 1; fi
			if [[ "$OS_TYPE" == "linux" ]]; then
				if command -v apt-get &>/dev/null; then apt-get update && apt-get install -y "${missing_deps[@]}";
				elif command -v yum &>/dev/null; then yum install -y "${missing_deps[@]}";
				elif command -v dnf &>/dev/null; then dnf install -y "${missing_deps[@]}";
				else echo -e "${RED}无法确定包管理器。请手动安装。${NC}"; exit 1; fi
			elif [[ "$OS_TYPE" == "alpine" ]]; then apk add --no-cache "${missing_deps[@]}"; fi
		elif [[ "$OS_TYPE" == "macos" ]]; then
			echo -e "${YELLOW}请使用 Homebrew 手动安装: brew install ${missing_deps[*]}${NC}"; exit 1
		fi
		for cmd in "${missing_deps[@]}"; do
			 if ! command -v "$cmd" &> /dev/null; then
				echo -e "${RED}依赖 '$cmd' 安装失败。请手动安装后重试。${NC}"; exit 1
			 fi
		done
	fi
}

get_arch() {
	case "$(uname -m)" in
		x86_64|amd64) echo "x86_64" ;; aarch64|arm64) echo "aarch64" ;;
		*) echo -e "${RED}错误: 不支持的架构: $(uname -m)${NC}"; exit 1 ;;
	esac
}

check_installed() {
	if [ ! -f "${INSTALL_DIR}/${CORE_BINARY_NAME}" ]; then
		echo -e "${YELLOW}EasyTier 尚未安装。请先选择选项 1。${NC}"; return 1
	fi; return 0
}

select_active_config_file() {
	if [ -n "${EASYTIER_CONFIG_FILE:-}" ]; then
		CONFIG_FILE="$EASYTIER_CONFIG_FILE"
		return 0
	fi
	if [ -f "$SERVICE_FILE" ]; then
		if [ -f "$NODE_CONFIG_FILE" ] && grep -Fq -- "$NODE_CONFIG_FILE" "$SERVICE_FILE"; then
			CONFIG_FILE="$NODE_CONFIG_FILE"
			return 0
		fi
		if [ -f "$DEFAULT_CONFIG_FILE" ] && grep -Fq -- "$DEFAULT_CONFIG_FILE" "$SERVICE_FILE"; then
			CONFIG_FILE="$DEFAULT_CONFIG_FILE"
			return 0
		fi
	fi
	if [ -f "$DEFAULT_CONFIG_FILE" ]; then
		CONFIG_FILE="$DEFAULT_CONFIG_FILE"
	elif [ -f "$NODE_CONFIG_FILE" ]; then
		CONFIG_FILE="$NODE_CONFIG_FILE"
	else
		CONFIG_FILE="$DEFAULT_CONFIG_FILE"
	fi
}

set_toml_value() {
	local key="$1" value="$2" file="$3" temp_file
	temp_file=$(mktemp)
	EASYTIER_TOML_VALUE="$value" awk -v key="$key" '
		BEGIN { updated = 0 }
		$0 ~ "^[[:space:]#]*" key "[[:space:]]*=" && !updated {
			print key " = " ENVIRON["EASYTIER_TOML_VALUE"]
			updated = 1
			next
		}
		{ print }
		END { if (!updated) print key " = " ENVIRON["EASYTIER_TOML_VALUE"] }
	' "$file" > "$temp_file" || { rm -f "$temp_file"; return 1; }
	mv "$temp_file" "$file"
}

set_top_level_toml_value() {
	local key="$1" value="$2" file="$3" temp_file
	temp_file=$(mktemp)
	EASYTIER_TOML_VALUE="$value" awk -v key="$key" '
		BEGIN { in_top_level = 1; updated = 0 }
		in_top_level && $0 ~ "^[[:space:]#]*" key "[[:space:]]*=" && !updated {
			print key " = " ENVIRON["EASYTIER_TOML_VALUE"]
			updated = 1
			next
		}
		in_top_level && /^[[:space:]]*\[/ {
			if (!updated) {
				print key " = " ENVIRON["EASYTIER_TOML_VALUE"]
				updated = 1
			}
			in_top_level = 0
		}
		{ print }
		END {
			if (!updated) print key " = " ENVIRON["EASYTIER_TOML_VALUE"]
		}
	' "$file" > "$temp_file" || { rm -f "$temp_file"; return 1; }
	mv "$temp_file" "$file"
}

toml_escape() {
	local value="$1"
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	printf '%s' "$value"
}

get_toml_string() {
	local key="$1" file="$2"
	awk -v key="$key" '
		$0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
			line = $0
			sub(/^[^=]*=[[:space:]]*"/, "", line)
			sub(/"[[:space:]]*$/, "", line)
			print line
			exit
		}
	' "$file"
}

get_top_level_toml_string() {
	local key="$1" file="$2"
	awk -v key="$key" '
		/^[[:space:]]*\[/ { exit }
		$0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
			line = $0
			sub(/^[^=]*=[[:space:]]*"/, "", line)
			sub(/"[[:space:]]*$/, "", line)
			print line
			exit
		}
	' "$file"
}

get_toml_value() {
	local key="$1" file="$2"
	awk -v key="$key" '
		$0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
			line = $0
			sub(/^[^=]*=[[:space:]]*/, "", line)
			sub(/[[:space:]]*$/, "", line)
			print line
			exit
		}
	' "$file"
}

validate_config_file() {
	local file="$1"
	if [ ! -x "${INSTALL_DIR}/${CORE_BINARY_NAME}" ]; then
		echo -e "${RED}无法校验配置：未找到 ${INSTALL_DIR}/${CORE_BINARY_NAME}。${NC}"
		return 1
	fi
	"${INSTALL_DIR}/${CORE_BINARY_NAME}" -c "$file" --check-config >/dev/null
}

commit_config_file() {
	local candidate="$1" backup_file
	if ! validate_config_file "$candidate"; then
		echo -e "${RED}配置校验失败，原配置未修改。${NC}"
		return 1
	fi
	backup_file=$(mktemp "${CONFIG_FILE}.bak.XXXXXX") || return 1
	cp -p "$CONFIG_FILE" "$backup_file" || { rm -f "$backup_file"; return 1; }
	install -m 600 "$candidate" "$CONFIG_FILE" || return 1
	echo -e "${GREEN}配置已更新，备份文件：${backup_file}${NC}"
	if [ -f "$SERVICE_FILE" ]; then
		restart_service
		echo -e "${GREEN}EasyTier 服务已重启。${NC}"
	fi
}

list_peers() {
	local file="${1:-$CONFIG_FILE}"
	awk '
		/^\[\[peer\]\][[:space:]]*$/ { in_peer = 1; next }
		/^\[/ { in_peer = 0 }
		in_peer && /^[[:space:]]*uri[[:space:]]*=/ {
			line = $0
			sub(/^[^=]*=[[:space:]]*"/, "", line)
			sub(/"[[:space:]]*$/, "", line)
			count++
			printf "%d\t%s\n", count, line
		}
	' "$file"
}

add_peer_to_file() {
	local file="$1" uri="$2"
	printf '\n[[peer]]\nuri = "%s"\n' "$(toml_escape "$uri")" >> "$file"
}

update_peer_in_file() {
	local file="$1" target="$2" uri="$3" temp_file
	temp_file=$(mktemp)
	EASYTIER_PEER_URI="$(toml_escape "$uri")" awk -v target="$target" '
		/^\[\[peer\]\][[:space:]]*$/ { peer++; in_target = (peer == target); print; next }
		/^\[/ { in_target = 0 }
		in_target && /^[[:space:]]*uri[[:space:]]*=/ { print "uri = \"" ENVIRON["EASYTIER_PEER_URI"] "\""; next }
		{ print }
	' "$file" > "$temp_file" || { rm -f "$temp_file"; return 1; }
	mv "$temp_file" "$file"
}

delete_peer_from_file() {
	local file="$1" target="$2" temp_file
	temp_file=$(mktemp)
	awk -v target="$target" '
		/^\[\[peer\]\][[:space:]]*$/ {
			peer++
			skipping = (peer == target)
			if (!skipping) print
			next
		}
		/^\[/ {
			if (skipping) skipping = 0
		}
		!skipping { print }
	' "$file" > "$temp_file" || { rm -f "$temp_file"; return 1; }
	mv "$temp_file" "$file"
}

valid_peer_uri() {
	[[ "$1" =~ ^(tcp|udp|wg|ws|wss)://[^[:space:]]+$ ]]
}

show_config() {
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在。${NC}"; return 1; }
	sed -E 's/^([[:space:]]*network_secret[[:space:]]*=[[:space:]]*).*/\1"***"/' "$CONFIG_FILE"
}

# --- 平台相关的服务管理功能 ---

create_service_file() {
    if [[ "$OS_TYPE" == "macos" || "$OS_TYPE" == "alpine" ]]; then
        touch "$LOG_FILE"
        chown root:root "$LOG_FILE" &>/dev/null
        chmod 644 "$LOG_FILE"
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        cat > "${SERVICE_FILE}" << EOL
[Unit]
Description=EasyTier Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/${CORE_BINARY_NAME} -c ${CONFIG_FILE}
# 使用 "always" 策略确保进程无论如何退出都会被重启，提供最强的守护
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL
    elif [[ "$OS_TYPE" == "alpine" ]]; then
        # 使用 OpenRC 的 supervise-daemon 实现真正的进程守护
        cat > "${SERVICE_FILE}" << EOL
#!/sbin/openrc-run
description="EasyTier Service with Supervisor"
supervisor=supervise-daemon
command="${INSTALL_DIR}/${CORE_BINARY_NAME}"
command_args="-c ${CONFIG_FILE}"
command_user="root"
pidfile="/var/run/${SERVICE_NAME}.pid"
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"
depend() {
	need net
	after net
}
EOL
        chmod +x "${SERVICE_FILE}";
    elif [[ "$OS_TYPE" == "macos" ]]; then
        cat > "${SERVICE_FILE}" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${CORE_BINARY_NAME}</string>
        <string>-c</string>
        <string>${CONFIG_FILE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
</dict>
</plist>
EOL
    fi
    echo -e "${GREEN}服务文件创建/更新成功: ${SERVICE_FILE}${NC}"
}

reload_service_daemon() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl daemon-reload; fi; }
start_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl start "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" start; elif [[ "$OS_TYPE" == "macos" ]]; then launchctl load "${SERVICE_FILE}" &>/dev/null; fi; }
stop_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl stop "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" stop; elif [[ "$OS_TYPE" == "macos" ]]; then launchctl unload "${SERVICE_FILE}" &>/dev/null; fi; }
restart_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl restart "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" restart; elif [[ "$OS_TYPE" == "macos" ]]; then stop_service; sleep 1; start_service; fi; }
enable_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl enable "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-update add "${SERVICE_NAME}" default; elif [[ "$OS_TYPE" == "macos" ]]; then start_service; fi; echo -e "${GREEN}服务已设为开机自启。${NC}"; }
disable_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl disable "${SERVICE_NAME}"; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-update del "${SERVICE_NAME}" default; elif [[ "$OS_TYPE" == "macos" ]]; then stop_service; fi; echo -e "${YELLOW}服务已取消开机自启。${NC}"; }
status_service() { if [[ "$OS_TYPE" == "linux" ]]; then systemctl status "${SERVICE_NAME}" --no-pager -l; elif [[ "$OS_TYPE" == "alpine" ]]; then rc-service "${SERVICE_NAME}" status; elif [[ "$OS_TYPE" == "macos" ]]; then if launchctl list | grep -q "${SERVICE_LABEL}"; then echo -e "${GREEN}EasyTier 服务 (${SERVICE_LABEL}) 正在运行。${NC}"; ps aux | grep "${CORE_BINARY_NAME}" | grep -v grep; else echo -e "${YELLOW}EasyTier 服务 (${SERVICE_LABEL}) 已停止。${NC}"; fi; fi; }
log_service() { if [[ "$OS_TYPE" == "linux" ]]; then journalctl -u "${SERVICE_NAME}" -f --no-pager; elif [[ "$OS_TYPE" == "alpine" || "$OS_TYPE" == "macos" ]]; then echo "正在显示日志文件: ${LOG_FILE}"; tail -f "${LOG_FILE}"; fi; }

# --- 主功能函数 ---
create_shortcut() {
	local SCRIPT_PATH; SCRIPT_PATH=$(realpath "$0" 2>/dev/null || (cd "$(dirname "$0")" && echo "$(pwd)/$(basename "$0")"))
	if [ -L "${ALIAS_PATH}" ] && [ "$(readlink "${ALIAS_PATH}")" = "${SCRIPT_PATH}" ]; then return 0; fi
	echo -e "${YELLOW}正在创建“et”快捷命令...${NC}"
	chmod +x "${SCRIPT_PATH}"
	ln -sf "${SCRIPT_PATH}" "${ALIAS_PATH}"
	if [ $? -eq 0 ]; then echo -e "${GREEN}成功! 现在你可以在终端中直接输入“et”来运行此脚本。${NC}"; else echo -e "${RED}创建快捷命令失败。请检查权限或 /usr/local/bin 是否在你的 PATH 中。${NC}"; fi
}

remove_shortcut() {
	if [ -L "${ALIAS_PATH}" ]; then rm -f "${ALIAS_PATH}" &>/dev/null; fi
}

update_manager_script() {
	local download_file staging_file backup_file
	download_file=$(mktemp) || return 1
	trap 'rm -f -- "${download_file}" "${staging_file:-}"' RETURN

	echo -e "${YELLOW}正在从 GitHub 下载最新版管理脚本...${NC}"
	if ! curl -fL --retry 3 --retry-delay 2 -o "$download_file" "$MANAGER_SOURCE_URL"; then
		echo -e "${RED}管理脚本下载失败，现有版本未修改。${NC}"
		return 1
	fi
	if ! head -n 1 "$download_file" | grep -Eq '^#!.*(ba)?sh'; then
		echo -e "${RED}下载内容不是有效的 Shell 脚本，现有版本未修改。${NC}"
		return 1
	fi
	if ! bash -n "$download_file"; then
		echo -e "${RED}新脚本语法校验失败，现有版本未修改。${NC}"
		return 1
	fi

	install -d -m 0755 "$MANAGER_INSTALL_DIR" "$(dirname "$ALIAS_PATH")"
	if [ -f "$MANAGER_INSTALL_PATH" ] && cmp -s "$download_file" "$MANAGER_INSTALL_PATH"; then
		ln -sfn "$MANAGER_INSTALL_PATH" "$ALIAS_PATH"
		echo -e "${GREEN}管理脚本已经是最新版本。${NC}"
		return 0
	fi

	staging_file=$(mktemp "${MANAGER_INSTALL_PATH}.new.XXXXXX") || return 1
	install -m 0755 "$download_file" "$staging_file" || return 1
	if [ -f "$MANAGER_INSTALL_PATH" ]; then
		backup_file="${MANAGER_INSTALL_PATH}.bak"
		cp -p "$MANAGER_INSTALL_PATH" "$backup_file" || return 1
	fi
	mv -f "$staging_file" "$MANAGER_INSTALL_PATH" || return 1
	staging_file=""
	ln -sfn "$MANAGER_INSTALL_PATH" "$ALIAS_PATH" || return 1
	echo -e "${GREEN}管理脚本已更新：${MANAGER_INSTALL_PATH}${NC}"
	[ -n "${backup_file:-}" ] && echo -e "${YELLOW}旧版本备份：${backup_file}${NC}"
	echo "请重新运行 et 使用新版本。"
	trap - RETURN
	rm -f -- "$download_file"
}

install_easytier() {
	echo -e "${GREEN}--- 开始安装或更新 EasyTier ---${NC}"
	local os_identifier="linux"; if [[ "$OS_TYPE" == "macos" ]]; then os_identifier="macos"; fi
	local arch; arch=$(get_arch)

	echo "1. 获取最新版本信息..."
	local latest_info; latest_info=$(curl -sL "$GITHUB_API_URL")
	if [ -z "$latest_info" ] || ! echo "$latest_info" | jq . >/dev/null 2>&1; then echo -e "${RED}错误: 无法从 GitHub API 获取版本信息。${NC}"; return 1; fi
	local search_prefix="easytier-${os_identifier}-${arch}"
	local asset_json; asset_json=$(echo "$latest_info" | jq ".assets[] | select(.name | startswith(\"${search_prefix}\") and endswith(\".zip\"))")
	if [ -z "$asset_json" ]; then echo -e "${RED}错误: 未能找到适用于 ${OS_TYPE}(${arch}) 的包。${NC}"; return 1; fi
	local download_url; download_url=$(echo "$asset_json" | jq -r '.browser_download_url')
	local actual_filename; actual_filename=$(echo "$asset_json" | jq -r '.name')
	local version; version=$(echo "$latest_info" | jq -r ".tag_name")
	echo "检测到版本: ${version}, 架构: ${arch}, 文件: ${actual_filename}"
	if [ -n "$GITHUB_PROXY" ]; then download_url="https://$GITHUB_PROXY/$download_url"; echo -e "${YELLOW}2. 使用代理下载: ${download_url}${NC}"; else echo "2. 直接下载: ${download_url}"; fi
	local temp_file; temp_file=$(mktemp)
	curl -L --progress-bar -o "$temp_file" "$download_url" || { echo -e "${RED}下载失败!${NC}"; rm -f "$temp_file"; return 1; }
	echo "3. 解压并安装..."
	local unzip_dir_name="easytier-${os_identifier}-${arch}"
	unzip -o "$temp_file" -d /tmp/ > /dev/null || { echo -e "${RED}解压失败!${NC}"; rm -f "$temp_file"; return 1; }
	local extracted_core="/tmp/${unzip_dir_name}/${CORE_BINARY_NAME}"; local extracted_cli="/tmp/${unzip_dir_name}/${CLI_BINARY_NAME}"
	if [ ! -f "$extracted_core" ] || [ ! -f "$extracted_cli" ]; then echo -e "${RED}错误: 在解压目录中未找到核心文件。${NC}"; rm -f "$temp_file"; rm -rf "/tmp/${unzip_dir_name}"; return 1; fi
	mkdir -p "$INSTALL_DIR"
	mv -f "$extracted_core" "${INSTALL_DIR}/${CORE_BINARY_NAME}"; mv -f "$extracted_cli" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
	chmod +x "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"
	rm -f "$temp_file"; rm -rf "/tmp/${unzip_dir_name}"
	
	echo -e "${GREEN}--- EasyTier ${version} 安装/更新成功! ---${NC}"
	create_shortcut
	
	if [ -f "$SERVICE_FILE" ]; then
		echo -e "${YELLOW}检测到现有服务，正在重启以应用更新...${NC}"; restart_service;
	fi
}

create_default_config() {
	local instance_name
	instance_name=$(toml_escape "$(hostname)")
	mkdir -p "$CONFIG_DIR"; umask 077; cat > "$CONFIG_FILE" << EOF
instance_name = "${instance_name}"
ipv4 = ""
dhcp = false
listeners = ["udp://0.0.0.0:11010", "tcp://0.0.0.0:11010", "wg://0.0.0.0:11011", "ws://0.0.0.0:11011/", "wss://0.0.0.0:11012/", "tcp://[::]:11010", "udp://[::]:11010"]
[network_identity]
network_name = ""
network_secret = ""
[flags]
default_protocol = "udp"
dev_name = ""
enable_encryption = true
enable_ipv6 = true
mtu = 1380
latency_first = true
enable_exit_node = false
no_tun = false
use_smoltcp = false
foreign_network_whitelist = "*"
disable_p2p = false
relay_all_peer_rpc = false
disable_udp_hole_punching = false
enableKcp_Proxy = true
EOF
	if [ $? -eq 0 ]; then chmod 600 "$CONFIG_FILE"; echo "已成功创建默认配置文件: ${CONFIG_FILE}"; return 0;
	else echo -e "${RED}错误: 创建配置文件失败!${NC}"; return 1; fi
}

deploy_new_network() { 
	check_installed || return 1
	read -p "请输入网络名称: " network_name
	read -r -s -p "请输入网络密钥: " network_secret; echo
	read -p "请输入此虚拟IP (回车则启用DHCP): " virtual_ip
	
	create_default_config || return 1
	
	set_toml_value "network_name" "\"$(toml_escape "$network_name")\"" "$CONFIG_FILE"
	set_toml_value "network_secret" "\"$(toml_escape "$network_secret")\"" "$CONFIG_FILE"
	
	if [ -z "$virtual_ip" ]; then
		echo -e "${YELLOW}未输入IP，将启用 DHCP 自动获取地址。${NC}"
		set_toml_value "dhcp" "true" "$CONFIG_FILE"
		set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"
	else
		echo -e "${GREEN}已设置静态IP: ${virtual_ip}${NC}"
		set_toml_value "dhcp" "false" "$CONFIG_FILE"
		set_toml_value "ipv4" "\"$(toml_escape "$virtual_ip")\"" "$CONFIG_FILE"
	fi
	validate_config_file "$CONFIG_FILE" || return 1

	create_service_file
	reload_service_daemon
	
	# [MODIFIED] 自动启用并重启服务
	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 新网络部署成功，服务已启动并设为开机自启! ---${NC}"
	
	sleep 2; status_service
}

join_existing_network() { 
	check_installed || return 1
	read -p "请输入网络名称: " network_name
	read -r -s -p "请输入网络密钥: " network_secret; echo
	read -p "请输入此节点虚拟IP (留空则启用DHCP): " virtual_ip
	read -p "请输入一个对端节点地址 (回车默认为 tcp://public.easytier.top:11010): " peer_address
	if [ -z "$peer_address" ]; then
		peer_address="tcp://public.easytier.top:11010"
		echo -e "${YELLOW}使用默认对端节点: ${peer_address}${NC}"
	fi

	create_default_config || return 1

	if ! valid_peer_uri "$peer_address"; then echo -e "${RED}对端地址格式无效。${NC}"; return 1; fi
	set_toml_value "network_name" "\"$(toml_escape "$network_name")\"" "$CONFIG_FILE"
	set_toml_value "network_secret" "\"$(toml_escape "$network_secret")\"" "$CONFIG_FILE"
	add_peer_to_file "$CONFIG_FILE" "$peer_address"

	if [ -z "$virtual_ip" ]; then
		echo -e "${YELLOW}未输入IP，将启用 DHCP 自动获取地址。${NC}"
		set_toml_value "dhcp" "true" "$CONFIG_FILE"
		set_toml_value "ipv4" "\"\"" "$CONFIG_FILE"
	else
		echo -e "${GREEN}已设置静态IP: ${virtual_ip}${NC}"
		set_toml_value "dhcp" "false" "$CONFIG_FILE"
		set_toml_value "ipv4" "\"$(toml_escape "$virtual_ip")\"" "$CONFIG_FILE"
	fi
	validate_config_file "$CONFIG_FILE" || return 1

	create_service_file
	reload_service_daemon

	# [MODIFIED] 自动启用并重启服务
	echo -e "${YELLOW}正在设置开机自启并启动服务...${NC}"
	enable_service
	restart_service
	echo -e "${GREEN}--- 已加入网络，服务已启动并设为开机自启! ---${NC}"

	sleep 2; status_service
}

update_network_config() {
	local temp_file current_name current_ip current_dhcp network_name network_secret virtual_ip
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在。${NC}"; return 1; }
	temp_file=$(mktemp)
	cp -p "$CONFIG_FILE" "$temp_file"
	current_name=$(get_toml_string "network_name" "$CONFIG_FILE")
	current_ip=$(get_toml_string "ipv4" "$CONFIG_FILE")
	current_dhcp=$(get_toml_value "dhcp" "$CONFIG_FILE")

	read -r -p "网络名称 [${current_name}]: " network_name
	network_name=${network_name:-$current_name}
	read -r -s -p "新网络密钥（留空保持不变）: " network_secret; echo
	if [ "$current_dhcp" = "true" ]; then
		read -r -p "虚拟 IP [当前 DHCP；留空保持，输入静态 IP/CIDR]: " virtual_ip
	else
		read -r -p "虚拟 IP [${current_ip}；留空保持，输入 dhcp 改为自动获取]: " virtual_ip
	fi

	set_toml_value "network_name" "\"$(toml_escape "$network_name")\"" "$temp_file"
	if [ -n "$network_secret" ]; then
		set_toml_value "network_secret" "\"$(toml_escape "$network_secret")\"" "$temp_file"
	fi
	if [ -n "$virtual_ip" ]; then
		if [ "$virtual_ip" = "dhcp" ]; then
			set_toml_value "dhcp" "true" "$temp_file"
			set_toml_value "ipv4" '""' "$temp_file"
		else
			set_toml_value "dhcp" "false" "$temp_file"
			set_toml_value "ipv4" "\"$(toml_escape "$virtual_ip")\"" "$temp_file"
		fi
	fi
	commit_config_file "$temp_file"
	local result=$?
	rm -f "$temp_file"
	return "$result"
}

update_instance_name() {
	local temp_file current_name instance_name result
	check_installed || return 1
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在。${NC}"; return 1; }
	current_name=$(get_top_level_toml_string "instance_name" "$CONFIG_FILE")
	current_name=${current_name:-$(hostname)}
	echo "当前服务配置文件: ${CONFIG_FILE}"
	read -r -p "节点名称/hostname [${current_name}]（留空保持不变）: " instance_name
	[ -n "$instance_name" ] || { echo "节点名称未修改。"; return 0; }

	temp_file=$(mktemp)
	cp -p "$CONFIG_FILE" "$temp_file"
	set_top_level_toml_value "instance_name" "\"$(toml_escape "$instance_name")\"" "$temp_file"
	commit_config_file "$temp_file"; result=$?
	rm -f "$temp_file"
	return "$result"
}

show_peer_list() {
	local peers
	peers=$(list_peers "$CONFIG_FILE")
	if [ -z "$peers" ]; then
		echo -e "${YELLOW}当前配置没有 Peer 节点。${NC}"
		return 1
	fi
	printf '%s\n' "$peers" | awk -F '\t' '{ printf " %s. %s\n", $1, $2 }'
}

add_peer_config() {
	local uri temp_file result
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在，请先部署或加入网络。${NC}"; return 1; }
	read -r -p "请输入 Peer 地址: " uri
	valid_peer_uri "$uri" || { echo -e "${RED}Peer 地址必须以 tcp://、udp://、wg://、ws:// 或 wss:// 开头。${NC}"; return 1; }
	temp_file=$(mktemp); cp -p "$CONFIG_FILE" "$temp_file"
	add_peer_to_file "$temp_file" "$uri"
	commit_config_file "$temp_file"; result=$?
	rm -f "$temp_file"
	return "$result"
}

update_peer_config() {
	local index uri count temp_file result
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在，请先部署或加入网络。${NC}"; return 1; }
	show_peer_list || return 1
	count=$(list_peers "$CONFIG_FILE" | wc -l | tr -d ' ')
	read -r -p "请输入要修改的节点编号: " index
	[[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "$count" ] || { echo -e "${RED}节点编号无效。${NC}"; return 1; }
	read -r -p "请输入新的 Peer 地址: " uri
	valid_peer_uri "$uri" || { echo -e "${RED}Peer 地址格式无效。${NC}"; return 1; }
	temp_file=$(mktemp); cp -p "$CONFIG_FILE" "$temp_file"
	update_peer_in_file "$temp_file" "$index" "$uri"
	commit_config_file "$temp_file"; result=$?
	rm -f "$temp_file"
	return "$result"
}

delete_peer_config() {
	local index count confirm temp_file result
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在。${NC}"; return 1; }
	show_peer_list || return 1
	count=$(list_peers "$CONFIG_FILE" | wc -l | tr -d ' ')
	read -r -p "请输入要删除的节点编号: " index
	[[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le "$count" ] || { echo -e "${RED}节点编号无效。${NC}"; return 1; }
	read -r -p "确认删除该 Peer 配置? (y/N): " confirm
	[[ "$confirm" =~ ^[Yy]$ ]] || { echo "操作已取消。"; return 0; }
	temp_file=$(mktemp); cp -p "$CONFIG_FILE" "$temp_file"
	delete_peer_from_file "$temp_file" "$index"
	commit_config_file "$temp_file"; result=$?
	rm -f "$temp_file"
	return "$result"
}

delete_network_config() {
	local confirm backup_file
	[ -f "$CONFIG_FILE" ] || { echo -e "${YELLOW}配置文件不存在。${NC}"; return 0; }
	read -r -p "确认停止服务并删除整个 EasyTier 配置? (输入 DELETE 确认): " confirm
	[ "$confirm" = "DELETE" ] || { echo "操作已取消。"; return 0; }
	backup_file=$(mktemp "${CONFIG_FILE}.deleted.XXXXXX") || return 1
	cp -p "$CONFIG_FILE" "$backup_file" || { rm -f "$backup_file"; return 1; }
	stop_service >/dev/null 2>&1 || true
	rm -f "$CONFIG_FILE"
	echo -e "${GREEN}配置已删除，服务已停止。备份文件：${backup_file}${NC}"
}

manage_config() {
	check_installed || return 1
	while true; do
		echo "---------------- 配置管理 ----------------"
		echo " 1. 更新网络名称、密钥或虚拟 IP"
		echo " 2. 新增 Peer 节点"
		echo " 3. 修改 Peer 节点"
		echo " 4. 删除 Peer 节点"
		echo " 5. 查看当前配置"
		echo " 6. 删除整个配置"
		echo " 0. 返回"
		read -r -p "请输入选项 [0-6]: " config_choice
		case "$config_choice" in
			1) update_network_config ;;
			2) add_peer_config ;;
			3) update_peer_config ;;
			4) delete_peer_config ;;
			5) show_config ;;
			6) delete_network_config ;;
			0) return 0 ;;
			*) echo -e "${RED}无效输入。${NC}" ;;
		esac
	done
}


manage_service() { check_installed || return 1; PS3="请选择操作: "; options=("启动" "停止" "重启" "状态" "设为开机自启" "取消开机自启" "查看日志" "返回"); select opt in "${options[@]}"; do case $opt in "启动") start_service && echo -e "${GREEN}服务已启动。${NC}"; break ;; "停止") stop_service && echo -e "${GREEN}服务已停止。${NC}"; break ;; "重启") restart_service && echo -e "${GREEN}服务已重启。${NC}"; break ;; "状态") status_service; break ;; "设为开机自启") enable_service; break ;; "取消开机自启") disable_service; break ;; "查看日志") log_service; break ;; "返回") break ;; esac; done; }

uninstall_easytier() { read -p "警告: 此操作将停止服务并删除所有相关文件。确定要卸载吗? (y/n): " confirm; if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then echo "操作已取消。"; return; fi; echo "正在停止并禁用服务..."; stop_service &> /dev/null; disable_service &> /dev/null; echo "正在删除文件..."; rm -f "${SERVICE_FILE}" "${INSTALL_DIR}/${CORE_BINARY_NAME}" "${INSTALL_DIR}/${CLI_BINARY_NAME}"; rm -rf "${CONFIG_DIR}"; remove_shortcut; if [[ "$OS_TYPE" == "linux" ]]; then systemctl daemon-reload; fi; if [[ "$OS_TYPE" == "macos" || "$OS_TYPE" == "alpine" ]]; then rm -f "$LOG_FILE"; fi; echo -e "${GREEN}EasyTier 已成功卸载。${NC}"; }

# --- 主菜单 ---
main() {
	case "$(uname)" in
		Linux) if [ -f /etc/alpine-release ]; then OS_TYPE="alpine"; SERVICE_FILE="/etc/init.d/${SERVICE_NAME}"; else OS_TYPE="linux"; SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"; fi ;;
		Darwin) OS_TYPE="macos"; SERVICE_FILE="/Library/LaunchDaemons/${SERVICE_LABEL}.plist"; ;;
		*) echo -e "${RED}错误: 不支持的操作系统: $(uname)${NC}"; exit 1 ;;
	esac
	select_active_config_file
	check_root; check_dependencies
	while true; do
		clear
		echo "======================================================="
		echo -e "   ${GREEN}EasyTier 跨平台部署 Debian/Ubuntu/Mac/Alpine${NC}"
		echo "======================================================="
		echo " 1. 安装或更新 EasyTier"
		echo " 2. 部署服务器 (服务节点)"
		echo " 3. 加入EasyTier组网网络"
		echo "-------------------------------------------------------"
		echo " 4. 管理EasyTier服务状态"
		echo " 5. 查看EasyTier配置文件"
		echo " 6. 查看EasyTier网络节点"
		echo " 7. 管理配置与 Peer 节点"
		echo "-------------------------------------------------------"
		echo " 8. 修改 EasyTier 节点名称 (hostname)"
		echo " 9. 更新管理脚本"
		echo "10. 卸载 EasyTier"
		echo " 0. 退出脚本"
		echo "======================================================="
		read -p "请输入选项 [0-10]: " choice
		
		echo
		
		case $choice in
			1) install_easytier ;;
			2) deploy_new_network ;;
			3) join_existing_network ;;
			4) manage_service ;;
			5) if check_installed; then show_config; fi ;;
			6) if check_installed; then ${INSTALL_DIR}/${CLI_BINARY_NAME} peer; fi ;;
			7) manage_config ;;
			8) update_instance_name ;;
			9) update_manager_script ;;
			10) uninstall_easytier ;;
			0) exit 0 ;;
			*) echo -e "${RED}无效输入${NC}" ;;
		esac
		echo -e "\n${YELLOW}按任意键返回主菜单...${NC}"; read -n 1 -s -r
	done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
