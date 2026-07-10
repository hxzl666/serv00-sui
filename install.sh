#!/usr/bin/env bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检测系统平台与架构
is_freebsd=0
uname_output=$(uname -a)
if echo "$uname_output" | grep -Eqi "freebsd"; then
    is_freebsd=1
fi

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo 'amd64' ;; # 默认使用 amd64
    esac
}

arch_name=$(arch)
echo "系统平台：$(uname -s)"
echo "系统架构：${arch_name}"

# 根据平台定义安装路径和权限限制
if [ $is_freebsd -eq 1 ]; then
    echo "检测到 FreeBSD 环境，将以非 root 模式安装..."
    INSTALL_DIR="$HOME/s-ui"
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
else
    # Linux 常规环境依然要求 root
    [[ $EUID -ne 0 ]] && echo -e "${red}致命错误：${plain} Linux 系统请使用 root 权限运行此脚本\n" && exit 1
    INSTALL_DIR="/usr/local/s-ui"
    BIN_DIR="/usr/bin"
fi

# 识别 Serv00 的三个入口地址
host_name=$(hostname)
entry_s="$host_name"
entry_web="$host_name"
entry_panel="$host_name"

if echo "$host_name" | grep -q "serv00.com"; then
    srv_num=$(echo "$host_name" | cut -d'.' -f1 | tr -cd '0-9')
    if [ -n "$srv_num" ]; then
        entry_s="s${srv_num}.serv00.com"
        entry_web="web${srv_num}.serv00.com"
        entry_panel="panel${srv_num}.serv00.com"
        echo -e "${green}成功识别 Serv00 服务器入口：${plain}"
        echo -e "  - SSH/节点域名入口: ${green}${entry_s}${plain}"
        echo -e "  - Web 备用域名入口: ${green}${entry_web}${plain}"
        echo -e "  - 管理面板域名入口: ${green}${entry_panel}${plain}"
    fi
fi

# 安装基础依赖（仅 Linux 需要，FreeBSD 假定已配置好基本环境）
install_base() {
    if [ $is_freebsd -eq 1 ]; then
        return 0
    fi
    
    # 获取 Linux 发行版
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
        source /usr/lib/os-release
        release=$ID
    else
        echo "无法识别 Linux 系统发行版！" >&2
        exit 1
    fi

    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

# 编译或下载后端二进制
prepare_sui_binary() {
    mkdir -p "${INSTALL_DIR}"
    
    if [ $is_freebsd -eq 1 ]; then
        echo -e "${yellow}检测到 FreeBSD 环境，正在尝试获取预编译发布包...${plain}"
        local last_version
        if [ $# == 0 ] || [ -z "$1" ]; then
            last_version=$(curl -Ls "https://api.github.com/repos/hxzl666/serv00-sui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [ -z "$last_version" ]; then
                last_version="latest"
            fi
            url="https://github.com/hxzl666/serv00-sui/releases/latest/download/s-ui-freebsd-amd64.tar.gz"
        else
            last_version=$1
            url="https://github.com/hxzl666/serv00-sui/releases/download/${last_version}/s-ui-freebsd-amd64.tar.gz"
        fi
        
        echo -e "正在尝试从发布页面下载: ${url}"
        wget -q -N --no-check-certificate -O /tmp/s-ui-freebsd.tar.gz ${url}
        if [ $? -eq 0 ] && [ -f /tmp/s-ui-freebsd.tar.gz ]; then
            echo -e "${green}成功获取预编译 FreeBSD 包，正在解压安装...${plain}"
            cd /tmp/
            tar -zxf s-ui-freebsd.tar.gz
            rm -f s-ui-freebsd.tar.gz
            cp -rf s-ui/* "${INSTALL_DIR}/"
            rm -rf s-ui
            cd "${cur_dir}"
        else
            echo -e "${yellow}未能从 Release 下载预编译包（可能暂未发布 Release 版），将自动回退到现场编译模式...${plain}"
            
            # 检查当前目录下是否有源码
            if [[ ! -f "main.go" || ! -d "web/html" ]]; then
                echo -e "${red}致命错误：当前目录未检测到源码，且未能从 GitHub 下载预编译包。${plain}"
                echo -e "请在此项目发布 Release 后再运行本一键命令，或上传完整源码至此目录。"
                exit 1
            fi
            
            # 检查是否有 Go 环境
            temp_go_installed=0
            if ! command -v go &>/dev/null; then
                echo -e "${yellow}未检测到系统安装了 Go，正在下载临时 Go 编译器进行现场构建...${plain}"
                wget -N --no-check-certificate -O /tmp/go-freebsd.tar.gz https://go.dev/dl/go1.22.2.freebsd-amd64.tar.gz
                if [ $? -ne 0 ]; then
                    echo -e "${red}下载 Go 编译器失败，请检查网络。${plain}"
                    exit 1
                fi
                tar -C /tmp/ -zxf /tmp/go-freebsd.tar.gz
                export PATH="/tmp/go/bin:$PATH"
                temp_go_installed=1
            fi
            
            echo -e "${yellow}正在编译 s-ui 后端二进制 (freebsd-amd64)...${plain}"
            go mod download
            tailscale_dir=$(go env GOPATH)/pkg/mod/github.com/sagernet/tailscale@*
            chmod -R +w "$tailscale_dir" 2>/dev/null || true
            router_file=$(find "$tailscale_dir" -name "router_freebsd.go" | head -n 1)
            if [ -n "$router_file" ] && [ -f "$router_file" ]; then
                sed -i '' 's|"github.com/sagernet/wireguard-go/tun"|// "github.com/sagernet/wireguard-go/tun"|g' "$router_file" 2>/dev/null || \
                sed -i 's|"github.com/sagernet/wireguard-go/tun"|// "github.com/sagernet/wireguard-go/tun"|g' "$router_file"
            fi
            
            go build -ldflags "-w -s" -tags "with_quic,with_grpc,with_utls,with_acme,with_gvisor" -o sui main.go
            if [ $? -ne 0 ]; then
                echo -e "${red}编译 s-ui 失败！请检查 Go 源码或环境。${plain}"
                # 清理临时 go
                [ $temp_go_installed -eq 1 ] && rm -rf /tmp/go
                exit 1
            fi
            
            # 移至安装目录
            mv -f sui "${INSTALL_DIR}/sui"
            
            # 清理临时 go
            [ $temp_go_installed -eq 1 ] && rm -rf /tmp/go
        fi
    else
        # Linux 环境直接下载官方预编译包
        echo -e "${yellow}正在下载 Linux 版 s-ui 二进制发行包...${plain}"
        local last_version
        if [ $# == 0 ] || [ -z "$1" ]; then
            # 获取最新版本号
            last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [ -z "$last_version" ]; then
                last_version="latest"
            fi
            url="https://github.com/alireza0/s-ui/releases/latest/download/s-ui-linux-${arch_name}.tar.gz"
        else
            last_version=$1
            url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-${arch_name}.tar.gz"
        fi
        
        echo -e "下载地址: ${url}"
        wget -N --no-check-certificate -O /tmp/s-ui.tar.gz ${url}
        if [ $? -ne 0 ]; then
            echo -e "${red}下载 s-ui 失败，请确认服务器能访问 Github。${plain}"
            exit 1
        fi
        
        cd /tmp/
        tar -zxf s-ui.tar.gz
        rm -f s-ui.tar.gz
        cp -rf s-ui/* "${INSTALL_DIR}/"
        rm -rf s-ui
        cd "${cur_dir}"
    fi
}

# 部署内核与依赖服务
prepare_kernel_and_configs() {
    mkdir -p "${INSTALL_DIR}/bin"
    mkdir -p "${INSTALL_DIR}/db"
    
    if [ $is_freebsd -eq 1 ]; then
        # FreeBSD 环境下需要使用 FreeBSD 版的 sing-box 内核
        echo -e "${yellow}正在下载适用于 FreeBSD 的 sing-box 内核...${plain}"
        local sb_ver="1.9.3"
        wget -N --no-check-certificate -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${sb_ver}/sing-box-${sb_ver}-freebsd-amd64.tar.gz"
        if [ $? -ne 0 ]; then
            echo -e "${red}下载 sing-box FreeBSD 内核失败，将尝试下载备用版本...${plain}"
            # 备用下载（例如直接从包中复制或其它低版本）
        else
            tar -C /tmp/ -zxf /tmp/sing-box.tar.gz
            mv -f /tmp/sing-box-${sb_ver}-freebsd-amd64/sing-box "${INSTALL_DIR}/bin/sing-box"
            chmod +x "${INSTALL_DIR}/bin/sing-box"
            rm -rf /tmp/sing-box.tar.gz /tmp/sing-box-${sb_ver}-freebsd-amd64
        fi
        
        # 复制控制脚本和数据库配置
        cp -f s-ui.sh "${INSTALL_DIR}/s-ui.sh"
        chmod +x "${INSTALL_DIR}/s-ui.sh"
        
        # 软链接到用户可执行路径
        ln -sf "${INSTALL_DIR}/s-ui.sh" "${BIN_DIR}/s-ui"
    else
        # Linux 正常处理内核与 systemd
        if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
            echo -e "${yellow}正在停止原 sing-box 服务...${plain}"
            systemctl stop sing-box
            rm -f "${INSTALL_DIR}/bin/sing-box"
        fi
        cp -f s-ui.sh "${INSTALL_DIR}/s-ui.sh"
        chmod +x "${INSTALL_DIR}/s-ui.sh"
        ln -sf "${INSTALL_DIR}/s-ui.sh" "${BIN_DIR}/s-ui"
        cp -f s-ui.service /etc/systemd/system/
        systemctl daemon-reload
    fi
}

# 引导用户输入初始化配置
config_after_install() {
    echo -e "${yellow}安装/编译完成！为安全起见，请配置您的面板访问设置。${plain}"
    
    # 提示端口输入
    echo -e "请输入${yellow}面板访问端口${plain} (确保已经在主机商后台开放):"
    read config_port
    while [ -z "$config_port" ]; do
        echo -e "${red}端口不能为空，请重新输入:${plain}"
        read config_port
    done
    
    echo -e "请输入${yellow}面板路径根${plain} (留空则默认为 /app/):"
    read config_path
    [ -z "$config_path" ] && config_path="/app/"
    # 确保以 / 开头和结尾
    [[ "$config_path" =~ ^/ ]] || config_path="/${config_path}"
    [[ "$config_path" =~ /$ ]] || config_path="${config_path}/"

    echo -e "请输入${yellow}订阅访问端口${plain} (确保已经在主机商后台开放):"
    read config_subPort
    while [ -z "$config_subPort" ]; do
        echo -e "${red}订阅端口不能为空，请重新输入:${plain}"
        read config_subPort
    done
    
    echo -e "请输入${yellow}订阅路径根${plain} (留空则默认为 /sub/):"
    read config_subPath
    [ -z "$config_subPath" ] && config_subPath="/sub/"
    [[ "$config_subPath" =~ ^/ ]] || config_subPath="/${config_subPath}"
    [[ "$config_subPath" =~ /$ ]] || config_subPath="${config_subPath}/"

    # 设置管理员账号密码
    echo -e "请输入${yellow}管理员用户名${plain} (默认 admin):"
    read config_account
    [ -z "$config_account" ] && config_account="admin"
    
    echo -e "请输入${yellow}管理员密码${plain} (默认 admin):"
    read config_password
    [ -z "$config_password" ] && config_password="admin"

    # 执行初始化写入设置
    echo -e "${yellow}正在初始化面板设置，请稍候...${plain}"
    
    # 迁移/重置配置
    "${INSTALL_DIR}/sui" migrate
    
    # 应用设置
    "${INSTALL_DIR}/sui" setting -port "${config_port}" -path "${config_path}" -subPort "${config_subPort}" -subPath "${config_subPath}"
    "${INSTALL_DIR}/sui" admin -username "${config_account}" -password "${config_password}"
}

# 进程启动与自启动保活设置
start_and_keepalive() {
    if [ $is_freebsd -eq 1 ]; then
        # 1. 编写保活脚本 cron.sh
        cat > "${INSTALL_DIR}/cron.sh" <<EOF
#!/usr/bin/env bash

# 运行路径
SUI_DIR="${INSTALL_DIR}"
SUI_BIN="\${SUI_DIR}/sui"
SUI_LOG="\${SUI_DIR}/sui.log"

if ! pgrep -f "\${SUI_BIN}" > /dev/null; then
    echo "[\$(date)] s-ui 进程不存在，正在重新启动..." >> "\${SUI_DIR}/cron.log"
    cd "\${SUI_DIR}"
    nohup ./\${SUI_BIN} > "\${SUI_LOG}" 2>&1 &
fi
EOF
        chmod +x "${INSTALL_DIR}/cron.sh"
        
        # 2. 自动配置 crontab
        echo -e "${yellow}正在将保活任务注册到 crontab 中...${plain}"
        (crontab -l 2>/dev/null; echo "* * * * * ${INSTALL_DIR}/cron.sh >/dev/null 2>&1") | sort -u | crontab -
        
        # 3. 运行服务
        cd "${INSTALL_DIR}"
        nohup ./sui > sui.log 2>&1 &
        sleep 2
        if pgrep -f "${INSTALL_DIR}/sui" > /dev/null; then
            echo -e "${green}s-ui 已经在后台启动成功，并已配置每分钟的 Crontab 保活守护！${plain}"
        else
            echo -e "${red}s-ui 后台启动失败，请运行 's-ui log' 查看日志。${plain}"
        fi
    else
        # Linux 下启用 systemd
        systemctl enable s-ui --now
        echo -e "${green}s-ui 服务已成功注册为 Systemd 并启动。${plain}"
    fi
}

# 展示最终的入口和访问指南
show_finish_info() {
    local real_port=$("${INSTALL_DIR}/sui" setting -show | grep "Port" | awk '{print $2}' | tr -d '\r\n')
    [ -z "$real_port" ] && real_port="未设定"
    
    local real_path=$("${INSTALL_DIR}/sui" setting -show | grep "Path" | awk '{print $2}' | tr -d '\r\n')
    [ -z "$real_path" ] && real_path="/app/"

    echo -e "\n${green}###############################################################${plain}"
    echo -e "${green}                 S-UI 面板安装与适配执行成功！                ${plain}"
    echo -e "${green}###############################################################${plain}"
    
    if [ $is_freebsd -eq 1 ]; then
        echo -e "\n由于是 FreeBSD / Serv00 节点环境，您可以使用以下 ${yellow}3 个域名入口${plain} 中的任意一个访问面板："
        echo -e "1) 节点主域名 (推荐)： ${green}http://${entry_s}:${real_port}${real_path}${plain}"
        echo -e "2) Web 备用域名：     ${green}http://${entry_web}:${real_port}${real_path}${plain}"
        echo -e "3) 管理面板域名：     ${green}http://${entry_panel}:${real_port}${real_path}${plain}"
        echo -e "\n同时，脚本已添加 Crontab 自启动保活，保障服务意外中断时能在一分钟内自动恢复运行。"
        echo -e "您也可以直接在命令行输入 ${yellow}s-ui${plain} 来调出管理菜单。"
    else
        echo -e "\n面板已启动，访问地址："
        echo -e "${green}http://${host_name}:${real_port}${real_path}${plain}"
    fi
    echo -e "${green}###############################################################${plain}\n"
}

# 执行安装流
echo -e "${green}开始执行 S-UI 安装适配脚本...${plain}"
install_base
prepare_sui_binary "$1"
prepare_kernel_and_configs
config_after_install
start_and_keepalive
show_finish_info
