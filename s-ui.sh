#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

SUI_GITHUB_PROXY=${SUI_GITHUB_PROXY:-}
if [[ -n "$SUI_GITHUB_PROXY" && "${SUI_GITHUB_PROXY: -1}" != "/" ]]; then
    SUI_GITHUB_PROXY="${SUI_GITHUB_PROXY}/"
fi

gh_url() {
    local url="$1"
    if [[ -n "$SUI_GITHUB_PROXY" ]]; then
        echo "${SUI_GITHUB_PROXY}${url}"
    else
        echo "$url"
    fi
}

function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

is_freebsd=0
uname_output=$(uname -a)
if echo "$uname_output" | grep -Eqi "freebsd"; then
    is_freebsd=1
fi

if [ $is_freebsd -eq 1 ]; then
    INSTALL_DIR="$HOME/s-ui"
    BIN_DIR="$HOME/.local/bin"
else
    INSTALL_DIR="/usr/local/s-ui"
    BIN_DIR="/usr/bin"
    # Linux 环境依然需要 root 权限
    [[ $EUID -ne 0 ]] && LOGE "错误：必须使用 root 权限运行此脚本！\n" && exit 1
fi

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法识别系统发行版，请联系作者！" >&2
    exit 1
fi

echo "系统发行版：$release"

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Default$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启 ${1} 服务" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press enter to return to the main menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls "$(gh_url "https://raw.githubusercontent.com/hxzlplp7/s-ui/main/install.sh")")
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "该功能将强制重装最新版本，数据不会丢失。是否继续？" "n"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls "$(gh_url "https://raw.githubusercontent.com/hxzlplp7/s-ui/main/install.sh")")
    if [[ $? == 0 ]]; then
        LOGI "更新完成，面板已自动重启。"
        exit 0
    fi
}

custom_version() {
    echo "请输入面板版本号（例如 0.0.1）："
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "面板版本不能为空，已退出。"
    exit 1
    fi

    download_link="$(gh_url "https://raw.githubusercontent.com/hxzlplp7/s-ui/main/install.sh")"

    install_command="bash <(curl -Ls $download_link) $panel_version"

    echo "正在下载并安装面板版本 $panel_version ..."
    eval $install_command
}

uninstall() {
    confirm "确定要卸载面板吗？" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop s-ui
    systemctl disable s-ui
    rm /etc/systemd/system/s-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm ${INSTALL_DIR}/config/ -rf
    rm ${INSTALL_DIR}/ -rf

    echo ""
    echo -e "卸载成功。如需删除本脚本，退出后执行 ${green}rm ${INSTALL_DIR} -f${plain}。"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_admin() {
    echo "不建议将管理员账号恢复为默认值。"
    confirm "确定要将管理员账号重置为默认值吗？" "n"
    if [[ $? == 0 ]]; then
        ${INSTALL_DIR}/sui admin -reset
    fi
    before_show_menu
}

set_admin() {
    echo "建议使用易记但安全的管理员账号密码。"
    read -p "请设置用户名：" config_account
    read -p "请设置密码：" config_password
    ${INSTALL_DIR}/sui admin -username ${config_account} -password ${config_password}
    before_show_menu
}

view_admin() {
    ${INSTALL_DIR}/sui admin -show
    before_show_menu
}

reset_setting() {
    confirm "确定要将面板设置重置为默认值吗？" "n"
    if [[ $? == 0 ]]; then
        ${INSTALL_DIR}/sui setting -reset
    fi
    before_show_menu
}

set_setting() {
    echo -e "请输入${yellow}面板端口${plain}（留空表示使用当前/默认值）："
    read config_port
    echo -e "请输入${yellow}面板路径${plain}（留空表示使用当前/默认值）："
    read config_path

    echo -e "请输入${yellow}订阅端口${plain}（留空表示使用当前/默认值）："
    read config_subPort
    echo -e "请输入${yellow}订阅路径${plain}（留空表示使用当前/默认值）：" 
    read config_subPath

    echo -e "${yellow}正在初始化，请稍候...${plain}"
    params=""
    [ -z "$config_port" ] || params="$params -port $config_port"
    [ -z "$config_path" ] || params="$params -path $config_path"
    [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
    [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
    ${INSTALL_DIR}/sui setting ${params}
    before_show_menu
}

view_setting() {
    ${INSTALL_DIR}/sui setting -show
    view_uri
    before_show_menu
}

view_uri() {
    info=$(${INSTALL_DIR}/sui uri)
    if [[ $? != 0 ]]; then
        LOGE "获取当前访问地址失败"
        before_show_menu
    fi
    LOGI "可通过以下地址访问面板："
    echo -e "${green}${info}${plain}"
}

start() {
    check_status $1
    if [[ $? == 0 ]]; then
        echo ""
        LOGI -e "${1} 正在运行，无需重复启动；如需重启，请选择 restart。"
    else
        if [ $is_freebsd -eq 1 ]; then
            cd "${INSTALL_DIR}"
            nohup ./sui > sui.log 2>&1 &
            sleep 2
        else
            systemctl start $1
            sleep 2
        fi
        check_status $1
        if [[ $? == 0 ]]; then
            LOGI "${1} 启动成功"
        else
            LOGE "${1} 启动失败，请稍后查看日志。"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status $1
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "${1} 已停止，无需重复停止。"
    else
        if [ $is_freebsd -eq 1 ]; then
            pkill -f "${INSTALL_DIR}/sui"
            sleep 2
        else
            systemctl stop $1
            sleep 2
        fi
        check_status $1
        if [[ $? == 1 ]]; then
            LOGI "${1} 停止成功"
        else
            LOGE "${1} 停止失败，请稍后查看日志。"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

restart() {
    if [ $is_freebsd -eq 1 ]; then
        stop $1 0
        start $1 0
    else
        systemctl restart $1
        sleep 2
        check_status $1
        if [[ $? == 0 ]]; then
            LOGI "${1} 重启成功"
        else
            LOGE "${1} 重启失败，可能启动超过 2 秒，请稍后查看日志。"
        fi
    fi
    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

status() {
    if [ $is_freebsd -eq 1 ]; then
        if pgrep -f "${INSTALL_DIR}/sui" > /dev/null; then
            pid=$(pgrep -f "${INSTALL_DIR}/sui")
            LOGI "s-ui 状态：运行中 (PID: $pid)"
        else
            LOGE "s-ui 状态：未运行"
        fi
    else
        systemctl status s-ui -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [ $is_freebsd -eq 1 ]; then
        (crontab -l 2>/dev/null; echo "* * * * * ${INSTALL_DIR}/cron.sh >/dev/null 2>&1") | sort -u | crontab -
        LOGI "已设置 S-UI 在 Crontab 中每分钟保活及开机自动拉起"
    else
        systemctl enable $1
        if [[ $? == 0 ]]; then
            LOGI "已设置 ${1} 开机自启"
        else
            LOGE "设置 ${1} 开机自启失败"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

disable() {
    if [ $is_freebsd -eq 1 ]; then
        crontab -l 2>/dev/null | grep -v "s-ui/cron.sh" | crontab -
        LOGI "已在 Crontab 中注销保活任务"
    else
        systemctl disable $1
        if [[ $? == 0 ]]; then
            LOGI "已取消 ${1} 开机自启"
        else
            LOGE "取消 ${1} 开机自启失败"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [ $is_freebsd -eq 1 ]; then
        tail -f -n 100 "${INSTALL_DIR}/sui.log"
    else
        journalctl -u $1.service -e --no-pager -f
    fi
    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O ${BIN_DIR}/s-ui -N --no-check-certificate "$(gh_url "https://raw.githubusercontent.com/hxzlplp7/s-ui/main/s-ui.sh")"
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查机器是否可访问 GitHub。"
        before_show_menu
    else
        chmod +x ${BIN_DIR}/s-ui
        LOGI "升级脚本成功，请重新运行脚本。" && exit 0
    fi
}

check_status() {
    if [ $is_freebsd -eq 1 ]; then
        if pgrep -f "${INSTALL_DIR}/sui" > /dev/null; then
            return 0
        else
            return 1
        fi
    fi
    if [[ ! -f "/etc/systemd/system/$1.service" ]]; then
        return 2
    fi
    temp=$(systemctl status "$1" | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    if [ $is_freebsd -eq 1 ]; then
        if crontab -l 2>/dev/null | grep -q "s-ui/cron.sh"; then
            return 0
        else
            return 1
        fi
    fi
    temp=$(systemctl is-enabled $1)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status s-ui
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请勿重复安装。"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status s-ui
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板。"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status $1
    case $? in
    0)
        echo -e "${1} 状态：${green}运行中${plain}"
        show_enable_status $1
        ;;
    1)
        echo -e "${1} 状态：${yellow}未运行${plain}"
        show_enable_status $1
        ;;
    2)
        echo -e "${1} 状态：${red}未安装${plain}"
        ;;
    esac
}

show_enable_status() {
    check_enabled $1
    if [[ $? == 0 ]]; then
        echo -e "${1} 开机自启：${green}是${plain}"
    else
        echo -e "${1} 开机自启：${red}否${plain}"
    fi
}

check_s-ui_status() {
    count=$(ps -ef | grep "sui" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_s-ui_status() {
    check_s-ui_status
    if [[ $? == 0 ]]; then
        echo -e "s-ui 状态：${green}运行中${plain}"
    else
        echo -e "s-ui 状态：${red}未运行${plain}"
    fi
}

bbr_menu() {
    echo -e "${green}\t1.${plain} 启用 BBR"
    echo -e "${green}\t2.${plain} 关闭 BBR"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择：" choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        ;;
    2)
        disable_bbr
        ;;
    *) echo "无效选择" ;;
    esac
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}当前未启用 BBR。${plain}"
        exit 0
    fi
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}已成功将 BBR 切换为 CUBIC。${plain}"
    else
        echo -e "${red}切换为 CUBIC 失败，请检查系统配置。${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR 已启用！${plain}"
        exit 0
    fi
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm ca-certificates
        ;;
    *)
        echo -e "${red}不支持的操作系统，请检查脚本并手动安装所需依赖。${plain}\n"
        exit 1
        ;;
    esac
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR 启用成功。${plain}"
    else
        echo -e "${red}BBR 启用失败，请检查系统配置。${plain}"
    fi
}

install_acme() {
    cd ~
    LOGI "正在安装 acme..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "安装 acme 失败"
        return 1
    else
        LOGI "安装 acme 成功"
    fi
    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} 申请 SSL 证书"
    echo -e "${green}\t2.${plain} 吊销证书"
    echo -e "${green}\t3.${plain} 强制续期"
    echo -e "${green}\t4.${plain} 生成自签名证书"
    read -p "请选择：" choice
    case "$choice" in
        1) ssl_cert_issue ;;
        2) 
            local domain=""
            read -p "请输入要吊销证书的域名：" domain
            ~/.acme.sh/acme.sh --revoke -d ${domain}
            LOGI "证书已吊销"
            ;;
        3)
            local domain=""
            read -p "请输入要强制续期 SSL 的域名：" domain
            ~/.acme.sh/acme.sh --renew -d ${domain} --force ;;
        4)
            generate_self_signed_cert
            ;;
        *) echo "无效选择" ;;
    esac
}

ssl_cert_issue() {
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "未检测到 acme.sh，将自动安装。"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "安装 acme 失败，请检查日志。"
            exit 1
        fi
    fi
    case "${release}" in
    ubuntu | debian | armbian)
        apt update && apt install socat -y
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install socat
        ;;
    fedora)
        dnf -y update && dnf -y install socat
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat
        ;;
    *)
        echo -e "${red}不支持的操作系统，请检查脚本并手动安装所需依赖。${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "安装 socat 失败，请检查日志。"
        exit 1
    else
        LOGI "安装 socat 成功..."
    fi

    local domain=""
    read -p "请输入你的域名：" domain
    LOGD "你的域名是：${domain}，正在检查..."
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')

    if [ ${currentCert} == ${domain} ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "系统已存在该域名证书，无法重复申请。当前证书信息："
        LOGI "$certInfo"
        exit 1
    else
        LOGI "域名检查通过，开始申请证书..."
    fi

    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    local WebPort=80
    read -p "请选择用于申请证书的端口（默认 80）：" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "输入的端口 ${WebPort} 无效，将使用默认端口。"
    fi
    LOGI "将使用端口 ${WebPort} 申请证书，请确保端口已放行。"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "证书申请失败，请检查日志。"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "证书申请成功，正在安装证书..."
    fi
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem

    if [ $? -ne 0 ]; then
        LOGE "证书安装失败，脚本退出。"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "证书安装成功，正在启用自动续期..."
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "自动续期配置失败，证书信息如下："
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "自动续期配置成功，证书信息如下："
        ls -lah cert/*
        chmod 755 $certPath/*
    fi
}

ssl_cert_issue_CF() {
    echo -E ""
    LOGD "******使用说明******"
    echo "1) 通过 Cloudflare 申请新证书"
    echo "2) 强制续期已有证书"
    echo "3) 返回菜单"
    read -p "请输入选项 [1-3]：" choice

    certPath="/root/cert-CF"

    case $choice in
        1|2)
            force_flag=""
            if [ "$choice" -eq 2 ]; then
                force_flag="--force"
                echo "正在强制重新签发 SSL 证书..."
            else
                echo "正在开始申请 SSL 证书..."
            fi
            
            LOGD "******使用说明******"
            LOGI "该 Acme 流程需要以下信息："
            LOGI "1. Cloudflare 注册邮箱"
            LOGI "2. Cloudflare Global API Key"
            LOGI "3. 已由 Cloudflare DNS 解析到当前服务器的域名"
            LOGI "4. 默认证书安装路径为 /root/cert"
            confirm "是否确认继续？[y/n]" "y"
            if [ $? -eq 0 ]; then
                if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
                    echo "未检测到 acme.sh，正在安装..."
                    install_acme
                    if [ $? -ne 0 ]; then
                        LOGE "安装 acme 失败，请检查日志。"
                        exit 1
                    fi
                fi

                CF_Domain=""
                if [ ! -d "$certPath" ]; then
                    mkdir -p $certPath
                else
                    rm -rf $certPath
                    mkdir -p $certPath
                fi

                LOGD "请设置域名："
                read -p "请输入你的域名：" CF_Domain
                LOGD "你设置的域名为：${CF_Domain}"

                CF_GlobalKey=""
                CF_AccountEmail=""
                LOGD "请设置 API Key："
                read -p "请输入你的 Key：" CF_GlobalKey
                LOGD "你输入的 API Key 为：${CF_GlobalKey}"

                LOGD "请设置注册邮箱："
                read -p "请输入你的邮箱：" CF_AccountEmail
                LOGD "你输入的邮箱为：${CF_AccountEmail}"

                ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [ $? -ne 0 ]; then
                    LOGE "设置默认 CA（Let's Encrypt）失败，脚本退出。"
                    exit 1
                fi

                export CF_Key="${CF_GlobalKey}"
                export CF_Email="${CF_AccountEmail}"

                ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} $force_flag --log
                if [ $? -ne 0 ]; then
                    LOGE "证书签发失败，脚本退出。"
                    exit 1
                else
                    LOGI "证书签发成功，正在安装..."
                fi

                mkdir -p ${certPath}/${CF_Domain}
                if [ $? -ne 0 ]; then
                    LOGE "创建目录失败：${certPath}/${CF_Domain}"
                    exit 1
                fi

                ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
                    --fullchain-file ${certPath}/${CF_Domain}/fullchain.pem \
                    --key-file ${certPath}/${CF_Domain}/privkey.pem

                if [ $? -ne 0 ]; then
                    LOGE "证书安装失败，脚本退出。"
                    exit 1
                else
                    LOGI "证书安装成功，正在启用自动更新..."
                fi

                ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                if [ $? -ne 0 ]; then
                    LOGE "自动更新配置失败，脚本退出。"
                    exit 1
                else
                    LOGI "证书已安装，并已开启自动续期。"
                    ls -lah ${certPath}/${CF_Domain}
                    chmod 755 ${certPath}/${CF_Domain}
                fi
            fi
            show_menu
            ;;
        3)
            echo "正在返回..."
            show_menu
            ;;
        *)
            echo "无效选择，请重新输入。"
            show_menu
            ;;
    esac
}

generate_self_signed_cert() {
    cert_dir="/etc/sing-box"
    mkdir -p "$cert_dir"
    LOGI "请选择证书类型："
    echo -e "${green}\t1.${plain} Ed25519 (*recommended*)"
    echo -e "${green}\t2.${plain} RSA 2048"
    echo -e "${green}\t3.${plain} RSA 4096"
    echo -e "${green}\t4.${plain} ECDSA prime256v1"
    echo -e "${green}\t5.${plain} ECDSA secp384r1"
    read -p "请输入选项 [1-5，默认 1]：" cert_type
    cert_type=${cert_type:-1}

    case "$cert_type" in
        1)
            algo="ed25519"
            key_opt="-newkey ed25519"
            ;;
        2)
            algo="rsa"
            key_opt="-newkey rsa:2048"
            ;;
        3)
            algo="rsa"
            key_opt="-newkey rsa:4096"
            ;;
        4)
            algo="ecdsa"
            key_opt="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1"
            ;;
        5)
            algo="ecdsa"
            key_opt="-newkey ec -pkeyopt ec_paramgen_curve:secp384r1"
            ;;
        *)
            algo="ed25519"
            key_opt="-newkey ed25519"
            ;;
    esac

    LOGI "正在生成自签名证书（$algo）..."
    sudo openssl req -x509 -nodes -days 3650 $key_opt \
        -keyout "${cert_dir}/self.key" \
        -out "${cert_dir}/self.crt" \
        -subj "/CN=myserver"
    if [[ $? -eq 0 ]]; then
        sudo chmod 600 "${cert_dir}/self."*
        LOGI "自签名证书生成成功！"
        LOGI "证书路径：${cert_dir}/self.crt"
        LOGI "私钥路径：${cert_dir}/self.key"
    else
        LOGE "自签名证书生成失败。"
    fi
    before_show_menu
}

show_usage() {
    echo -e "S-UI 管理脚本用法"
    echo -e "------------------------------------------"
    echo -e "子命令：" 
    echo -e "s-ui              - 管理脚本主菜单"
    echo -e "s-ui start        - 启动 s-ui"
    echo -e "s-ui stop         - 停止 s-ui"
    echo -e "s-ui restart      - 重启 s-ui"
    echo -e "s-ui status       - 查看 s-ui 状态"
    echo -e "s-ui enable       - 设置开机自启"
    echo -e "s-ui disable      - 取消开机自启"
    echo -e "s-ui log          - 查看 s-ui 日志"
    echo -e "s-ui update       - 更新"
    echo -e "s-ui install      - 安装"
    echo -e "s-ui uninstall    - 卸载"
    echo -e "s-ui help         - 查看脚本用法"
    echo -e "------------------------------------------"
}

show_menu() {
  echo -e "
  ${green}S-UI 管理脚本 ${plain}
————————————————————————————————
  ${green}0.${plain} 退出
————————————————————————————————
  ${green}1.${plain} 安装
  ${green}2.${plain} 更新
  ${green}3.${plain} 指定版本安装
  ${green}4.${plain} 卸载
————————————————————————————————
  ${green}5.${plain} 重置管理员账号为默认
  ${green}6.${plain} 设置管理员账号
  ${green}7.${plain} 查看管理员账号
————————————————————————————————
  ${green}8.${plain} 重置面板设置
  ${green}9.${plain} 设置面板参数
  ${green}10.${plain} 查看面板设置
————————————————————————————————
  ${green}11.${plain} 启动 S-UI
  ${green}12.${plain} 停止 S-UI
  ${green}13.${plain} 重启 S-UI
  ${green}14.${plain} 查看 S-UI 状态
  ${green}15.${plain} 查看 S-UI 日志
  ${green}16.${plain} 启用 S-UI 开机自启
  ${green}17.${plain} 关闭 S-UI 开机自启
————————————————————————————————
  ${green}18.${plain} BBR 开关
  ${green}19.${plain} SSL 证书管理
  ${green}20.${plain} Cloudflare SSL 证书
————————————————————————————————
 "
    show_status s-ui
    echo && read -p "请输入选项 [0-20]：" num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && custom_version
        ;;
    4)
        check_install && uninstall
        ;;
    5)
        check_install && reset_admin
        ;;
    6)
        check_install && set_admin
        ;;
    7)
        check_install && view_admin
        ;;
    8)
        check_install && reset_setting
        ;;
    9)
        check_install && set_setting
        ;;
    10)
        check_install && view_setting
        ;;
    11)
        check_install && start s-ui
        ;;
    12)
        check_install && stop s-ui
        ;;
    13)
        check_install && restart s-ui
        ;;
    14)
        check_install && status s-ui
        ;;
    15)
        check_install && show_log s-ui
        ;;
    16)
        check_install && enable s-ui
        ;;
    17)
        check_install && disable s-ui
        ;;
    18)
        bbr_menu
        ;;
    19)
        ssl_cert_issue_main
        ;;
    20)
        ssl_cert_issue_CF
        ;;
    *)
        LOGE "请输入正确的编号 [0-20]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start s-ui 0
        ;;
    "stop")
        check_install 0 && stop s-ui 0
        ;;
    "restart")
        check_install 0 && restart s-ui 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable s-ui 0
        ;;
    "disable")
        check_install 0 && disable s-ui 0
        ;;
    "log")
        check_install 0 && show_log s-ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
