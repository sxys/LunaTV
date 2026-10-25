#!/usr/bin/env bash
# ==============================================================================
# LunaTV VPS 一键自动化部署脚本
# 适用系统: Ubuntu 20.04+, Debian 11+, CentOS 7+, Rocky/AlmaLinux
# ==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}             LunaTV VPS 一键部署向导                ${NC}"
echo -e "${CYAN}====================================================${NC}"

# 1. 检查是否为 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!] 请使用 sudo 或 root 用户运行此脚本${NC}"
  exit 1
fi

# 2. 检测并安装 Docker & Docker Compose
check_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}[*] 未检测到 Docker，正在自动安装 Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo -e "${GREEN}[✓] Docker 安装成功！${NC}"
  else
    echo -e "${GREEN}[✓] Docker 已安装${NC}"
  fi

  if ! docker compose version &>/dev/null; then
    echo -e "${YELLOW}[*] 正在安装 Docker Compose 插件...${NC}"
    apt-get update && apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null || true
    if ! docker compose version &>/dev/null; then
      echo -e "${RED}[✗] Docker Compose 插件安装失败，请手动安装后重试。${NC}"
      exit 1
    fi
  fi
  echo -e "${GREEN}[✓] Docker Compose 已就绪: $(docker compose version)${NC}"
}

# 3. 检查并引导配置 .env
setup_env() {
  if [ ! -f .env ]; then
    echo -e "\n${YELLOW}[*] 未检测到 .env 配置文件，开始初始化配置...${NC}"
    cp .env.example .env

    read -rp "请输入管理员账号 (默认: admin): " input_user
    ADMIN_USER=${input_user:-admin}
    sed -i "s|^USERNAME=.*|USERNAME=${ADMIN_USER}|" .env

    read -rp "请输入管理员密码 (建议至少8位): " input_pass
    while [ -z "$input_pass" ]; do
      echo -e "${RED}[!] 密码不能为空，请输入管理员密码：${NC}"
      read -rp "请输入管理员密码: " input_pass
    done
    sed -i "s|^PASSWORD=.*|PASSWORD=${input_pass}|" .env

    echo -e "\n${YELLOW}提示: 必须先在域名服务商处将域名的 A 记录解析到此 VPS 的公网 IP！${NC}"
    read -rp "请输入绑定的完整域名 (例如 tv.example.com): " input_domain
    while [ -z "$input_domain" ]; do
      echo -e "${RED}[!] 域名不能为空，请输入域名：${NC}"
      read -rp "请输入绑定的完整域名: " input_domain
    done
    # 去除可能误输入的协议头与斜杠
    CLEAN_DOMAIN=$(echo "$input_domain" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    sed -i "s|^DOMAIN=.*|DOMAIN=${CLEAN_DOMAIN}|" .env
    sed -i "s|^SITE_BASE=.*|SITE_BASE=https://${CLEAN_DOMAIN}|" .env

    echo -e "${GREEN}[✓] 配置文件 .env 生成完毕！${NC}"
  else
    echo -e "${GREEN}[✓] 检测到现有 .env 配置文件，将使用现有配置。${NC}"
  fi
}

# 4. 启动服务
start_services() {
  echo -e "\n${YELLOW}[*] 正在拉取 Docker 镜像并启动服务...${NC}"
  docker compose down 2>/dev/null || true
  docker compose pull
  docker compose up -d

  echo -e "\n${GREEN}====================================================${NC}"
  echo -e "${GREEN}             🎉 LunaTV 服务启动成功！                ${NC}"
  echo -e "${GREEN}====================================================${NC}"
  
  source .env
  echo -e "访问地址 (HTTPS): ${CYAN}https://${DOMAIN}${NC}"
  echo -e "备用直接访问:    ${CYAN}http://$(curl -s ifconfig.me 2>/dev/null || echo 'VPS_IP'):${PORT:-3000}${NC}"
  echo -e "管理员账号:      ${YELLOW}${USERNAME}${NC}"
  echo -e "管理员密码:      ${YELLOW}${PASSWORD}${NC}"
  echo -e "----------------------------------------------------"
  echo -e "【温馨提醒】"
  echo -e "1. 请确保 VPS 防火墙/安全组已放行 ${YELLOW}80、443、3000${NC} 端口。"
  echo -e "2. 首次通过 HTTPS 访问时，Caddy 会自动申请 Let's Encrypt 证书（约需 5~10 秒）。"
  echo -e "3. 项目部署完成后为空壳，登录后台设置播放源即可开始使用。"
  echo -e "----------------------------------------------------"
  echo -e "常用运维命令:"
  echo -e "  查看服务日志:   docker compose logs -f"
  echo -e "  更新到最新版本: ./deploy.sh update"
  echo -e "  重启服务:       docker compose restart"
  echo -e "  停止服务:       docker compose down"
  echo -e "====================================================\n"
}

# 5. 更新命令
update_services() {
  echo -e "${YELLOW}[*] 正在更新 LunaTV 镜像并重启服务...${NC}"
  docker compose pull
  docker compose up -d --remove-orphans
  echo -e "${GREEN}[✓] 更新完成并已重新启动！${NC}"
}

# 命令分发
case "$1" in
  update)
    update_services
    ;;
  restart)
    docker compose restart
    ;;
  stop)
    docker compose down
    ;;
  logs)
    docker compose logs -f
    ;;
  *)
    check_docker
    setup_env
    start_services
    ;;
esac
