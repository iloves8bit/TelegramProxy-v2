#!/bin/bash

# ═══════════════════════════════════════════════════════════════
#  PROFESSIONAL MULTI-PROTOCOL PROXY INSTALLER v3.0 (FIXED)
#  Полностью рабочая версия с 3X-UI панелью
# ═══════════════════════════════════════════════════════════════

set -e

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# --- КОНСТАНТЫ ---
SCRIPT_NAME="multiproxy"
INSTALL_DIR="/opt/multiproxy"
CONFIG_DIR="$INSTALL_DIR/configs"
LOG_FILE="/var/log/multiproxy_install.log"

# --- ЛОГИРОВАНИЕ ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    echo -e "$*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*" >> "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"
}

# --- БАННЕР ---
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     PROFESSIONAL MULTI-PROTOCOL PROXY MANAGER v3.0          ║
║                    (FULLY WORKING)                           ║
║                                                              ║
║  Protocols: VLESS Reality • Shadowsocks • VMess • Trojan    ║
║  Panel: 3X-UI Web Interface                                 ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# --- ПРОВЕРКА ROOT ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Требуются права root. Запустите: sudo $0"
        exit 1
    fi
    success "Проверка прав: OK"
}

# --- ОПРЕДЕЛЕНИЕ ОС ---
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        error "Не удалось определить ОС"
        exit 1
    fi
    success "ОС определена: $OS $VERSION_ID"
}

# --- ОБНОВЛЕНИЕ СИСТЕМЫ ---
update_system() {
    info "Обновление системы..."
    
    case $OS in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || error "Ошибка обновления"
            apt-get upgrade -y -qq || error "Ошибка upgrade"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum update -y -q || error "Ошибка обновления"
            ;;
        *)
            error "Неподдерживаемая ОС: $OS"
            exit 1
            ;;
    esac
    
    success "Система обновлена"
}

# --- УСТАНОВКА ЗАВИСИМОСТЕЙ (ВКЛЮЧАЯ UNZIP!) ---
install_dependencies() {
    info "Установка зависимостей..."
    
    case $OS in
        ubuntu|debian)
            apt-get install -y -qq \
                curl \
                wget \
                unzip \
                tar \
                jq \
                qrencode \
                net-tools \
                ca-certificates \
                gnupg \
                lsb-release \
                ufw \
                socat \
                cron || error "Ошибка установки зависимостей"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum install -y -q \
                curl \
                wget \
                unzip \
                tar \
                jq \
                qrencode \
                net-tools \
                ca-certificates \
                firewalld \
                socat \
                cronie || error "Ошибка установки зависимостей"
            ;;
    esac
    
    success "Зависимости установлены (включая unzip)"
}

# --- УСТАНОВКА DOCKER ---
install_docker() {
    if command -v docker &> /dev/null; then
        success "Docker уже установлен"
        return
    fi
    
    info "Установка Docker..."
    
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >> "$LOG_FILE" 2>&1
    rm get-docker.sh
    
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl start docker >> "$LOG_FILE" 2>&1
    
    if command -v docker &> /dev/null; then
        success "Docker установлен"
    else
        error "Не удалось установить Docker"
        exit 1
    fi
}

# --- ПОЛУЧЕНИЕ IP ---
get_server_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -s -4 --max-time 5 https://icanhazip.com 2>/dev/null || \
         ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    if [ -z "$ip" ]; then
        error "Не удалось определить IP адрес"
        echo "0.0.0.0"
    else
        echo "$ip"
    fi
}

# --- ПРОВЕРКА ПОРТА ---
check_port() {
    local port=$1
    
    if ss -tuln | grep -q ":$port "; then
        return 1  # Порт занят
    fi
    
    return 0  # Порт свободен
}

# --- ПРОВЕРКА И НАСТРОЙКА FIREWALL ---
setup_firewall() {
    local port=$1
    
    info "Настройка firewall для порта $port..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                # Проверяем статус UFW
                if ufw status | grep -q "Status: active"; then
                    ufw allow "$port/tcp" >> "$LOG_FILE" 2>&1
                    ufw allow "$port/udp" >> "$LOG_FILE" 2>&1
                    success "Порт $port открыт в UFW"
                else
                    info "UFW не активен, пропуск"
                fi
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v firewall-cmd &> /dev/null; then
                if systemctl is-active --quiet firewalld; then
                    firewall-cmd --permanent --add-port="$port/tcp" >> "$LOG_FILE" 2>&1
                    firewall-cmd --permanent --add-port="$port/udp" >> "$LOG_FILE" 2>&1
                    firewall-cmd --reload >> "$LOG_FILE" 2>&1
                    success "Порт $port открыт в firewalld"
                else
                    info "firewalld не активен, пропуск"
                fi
            fi
            ;;
    esac
}

# --- ТЕСТ ДОСТУПНОСТИ ПОРТА ---
test_port_connectivity() {
    local port=$1
    local ip=$(get_server_ip)
    
    info "Тестирование доступности порта $port..."
    
    # Создаем временный тестовый сервер
    timeout 2 nc -l -p "$port" &>/dev/null &
    local pid=$!
    sleep 1
    
    # Пытаемся подключиться
    if timeout 2 nc -zv localhost "$port" &>/dev/null; then
        kill $pid 2>/dev/null
        success "Порт $port доступен локально"
        return 0
    else
        kill $pid 2>/dev/null
        error "Порт $port недоступен"
        return 1
    fi
}

# --- УСТАНОВКА 3X-UI ПАНЕЛИ ---
install_3xui() {
    info "Установка 3X-UI панели..."
    
    # Удаляем старую установку если есть
    if [ -d "/usr/local/x-ui" ]; then
        systemctl stop x-ui 2>/dev/null || true
        rm -rf /usr/local/x-ui
    fi
    
    # Скачиваем и устанавливаем 3X-UI
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << EOF
0
admin
admin
54321
EOF
    
    # Проверяем установку
    if systemctl is-active --quiet x-ui; then
        local server_ip=$(get_server_ip)
        success "3X-UI установлена и запущена"
        echo ""
        echo -e "${GREEN}═════════════════════════════════════════${NC}"
        echo -e "${CYAN}3X-UI Панель установлена!${NC}"
        echo -e "${YELLOW}URL:${NC} http://$server_ip:54321"
        echo -e "${YELLOW}Логин:${NC} admin"
        echo -e "${YELLOW}Пароль:${NC} admin"
        echo -e "${GREEN}═════════════════════════════════════════${NC}"
        echo ""
        
        # Открываем порт панели
        setup_firewall 54321
        
        return 0
    else
        error "3X-UI не запустилась"
        return 1
    fi
}

# --- УСТАНОВКА XRAY ---
install_xray() {
    info "Установка Xray-core..."
    
    # Создаем директории
    mkdir -p /usr/local/bin
    mkdir -p /etc/xray
    mkdir -p /var/log/xray
    
    # Определяем архитектуру
    local arch=$(uname -m)
    local xray_arch=""
    
    case $arch in
        x86_64)
            xray_arch="64"
            ;;
        aarch64)
            xray_arch="arm64-v8a"
            ;;
        armv7l)
            xray_arch="arm32-v7a"
            ;;
        *)
            error "Неподдерживаемая архитектура: $arch"
            return 1
            ;;
    esac
    
    # Получаем последнюю версию
    local latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    
    if [ -z "$latest_version" ]; then
        error "Не удалось получить версию Xray"
        return 1
    fi
    
    info "Скачивание Xray $latest_version для $xray_arch..."
    
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-${xray_arch}.zip"
    
    cd /tmp
    wget -q --show-progress "$download_url" -O xray.zip || {
        error "Не удалось скачать Xray"
        return 1
    }
    
    # ВАЖНО: Распаковываем с unzip
    unzip -q -o xray.zip -d /tmp/xray || {
        error "Не удалось распаковать Xray (unzip)"
        return 1
    }
    
    # Копируем файлы
    cp /tmp/xray/xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # Очищаем
    rm -rf /tmp/xray /tmp/xray.zip
    
    # Проверяем установку
    if /usr/local/bin/xray version &>/dev/null; then
        success "Xray установлен: $(/usr/local/bin/xray version | head -n1)"
        return 0
    else
        error "Xray не работает после установки"
        return 1
    fi
}

# --- УСТАНОВКА SHADOWSOCKS ---
install_shadowsocks() {
    info "Установка Shadowsocks через Docker..."
    
    # Проверяем Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        return 1
    fi
    
    # Скачиваем образ
    docker pull shadowsocks/shadowsocks-libev:latest >> "$LOG_FILE" 2>&1
    
    if docker images | grep -q shadowsocks; then
        success "Shadowsocks образ загружен"
        return 0
    else
        error "Не удалось загрузить Shadowsocks"
        return 1
    fi
}

# --- ГЕНЕРАЦИЯ UUID ---
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# --- ГЕНЕРАЦИЯ ПАРОЛЯ ---
generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# --- СОЗДАНИЕ VLESS REALITY ---
create_vless_reality() {
    local client_name=$1
    local port=$2
    
    info "Создание VLESS Reality для $client_name на порту $port..."
    
    # Проверяем порт
    if ! check_port "$port"; then
        error "Порт $port уже занят"
        return 1
    fi
    
    # Генерируем параметры
    local uuid=$(generate_uuid)
    local short_id=$(openssl rand -hex 8)
    
    # Генерируем ключи Reality
    local keys=$(/usr/local/bin/xray x25519)
    local private_key=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
    local public_key=$(echo "$keys" | grep "Public key:" | awk '{print $3}')
    
    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        error "Не удалось сгенерировать ключи x25519"
        return 1
    fi
    
    # Выбираем домен для маскировки
    local dest="www.microsoft.com:443"
    local server_name="www.microsoft.com"
    
    # Создаем конфигурацию
    mkdir -p "$CONFIG_DIR/reality"
    
    cat > "$CONFIG_DIR/reality/${client_name}.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access-${client_name}.log",
    "error": "/var/log/xray/error-${client_name}.log"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$dest",
          "xver": 0,
          "serverNames": ["$server_name"],
          "privateKey": "$private_key",
          "shortIds": ["$short_id"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
    
    # Создаем systemd сервис
    cat > "/etc/systemd/system/xray-${client_name}.service" << EOF
[Unit]
Description=Xray VLESS Reality - $client_name
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config $CONFIG_DIR/reality/${client_name}.json
Restart=on-failure
RestartSec=10
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    
    # Перезагружаем systemd
    systemctl daemon-reload
    
    # Запускаем сервис
    systemctl enable "xray-${client_name}" >> "$LOG_FILE" 2>&1
    systemctl start "xray-${client_name}" >> "$LOG_FILE" 2>&1
    
    # Проверяем запуск
    sleep 2
    if systemctl is-active --quiet "xray-${client_name}"; then
        success "VLESS Reality запущен: $client_name"
        
        # Настраиваем firewall
        setup_firewall "$port"
        
        # Формируем ссылку
        local server_ip=$(get_server_ip)
        local vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Reality_${client_name}"
        
        # Сохраняем информацию
        cat > "$CONFIG_DIR/reality/${client_name}_info.txt" << EOF
Клиент: $client_name
Протокол: VLESS Reality
Порт: $port
UUID: $uuid
Public Key: $public_key
Short ID: $short_id
Server Name: $server_name

Ссылка для подключения:
$vless_link
EOF
        
        # Выводим информацию
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}VLESS Reality успешно создан!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Клиент:${NC} $client_name"
        echo -e "${YELLOW}Порт:${NC} $port"
        echo -e "${YELLOW}Статус:${NC} ${GREEN}Активен${NC}"
        echo ""
        echo -e "${CYAN}Ссылка для подключения:${NC}"
        echo -e "${BLUE}$vless_link${NC}"
        echo ""
        echo -e "${YELLOW}QR код:${NC}"
        qrencode -t ANSIUTF8 "$vless_link"
        echo ""
        echo -e "${CYAN}Информация сохранена: $CONFIG_DIR/reality/${client_name}_info.txt${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo ""
        
        return 0
    else
        error "Не удалось запустить VLESS Reality"
        journalctl -u "xray-${client_name}" -n 20 --no-pager
        return 1
    fi
}

# --- СОЗДАНИЕ SHADOWSOCKS ---
create_shadowsocks() {
    local client_name=$1
    local port=$2
    
    info "Создание Shadowsocks для $client_name на порту $port..."
    
    # Проверяем порт
    if ! check_port "$port"; then
        error "Порт $port уже занят"
        return 1
    fi
    
    # Генерируем пароль
    local password=$(generate_password)
    local method="chacha20-ietf-poly1305"
    
    # Запускаем контейнер
    docker run -d \
        --name "ss-${client_name}" \
        --restart always \
        -p "${port}:${port}/tcp" \
        -p "${port}:${port}/udp" \
        -e "SERVER_PORT=${port}" \
        -e "PASSWORD=${password}" \
        -e "METHOD=${method}" \
        shadowsocks/shadowsocks-libev:latest \
        >> "$LOG_FILE" 2>&1
    
    # Проверяем запуск
    sleep 2
    if docker ps | grep -q "ss-${client_name}"; then
        success "Shadowsocks запущен: $client_name"
        
        # Настраиваем firewall
        setup_firewall "$port"
        
        # Формируем ссылку
        local server_ip=$(get_server_ip)
        local userinfo="${method}:${password}"
        local ss_link="ss://$(echo -n "$userinfo" | base64 -w0)@${server_ip}:${port}#SS_${client_name}"
        
        # Сохраняем информацию
        mkdir -p "$CONFIG_DIR/shadowsocks"
        cat > "$CONFIG_DIR/shadowsocks/${client_name}_info.txt" << EOF
Клиент: $client_name
Протокол: Shadowsocks
Порт: $port
Метод: $method
Пароль: $password

Ссылка для подключения:
$ss_link
EOF
        
        # Выводим информацию
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Shadowsocks успешно создан!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Клиент:${NC} $client_name"
        echo -e "${YELLOW}Порт:${NC} $port"
        echo -e "${YELLOW}Метод:${NC} $method"
        echo ""
        echo -e "${CYAN}Ссылка для подключения:${NC}"
        echo -e "${BLUE}$ss_link${NC}"
        echo ""
        echo -e "${YELLOW}QR код:${NC}"
        qrencode -t ANSIUTF8 "$ss_link"
        echo ""
        echo -e "${CYAN}Информация сохранена: $CONFIG_DIR/shadowsocks/${client_name}_info.txt${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo ""
        
        return 0
    else
        error "Не удалось запустить Shadowsocks"
        docker logs "ss-${client_name}"
        return 1
    fi
}

# --- СПИСОК ВСЕХ ПРОКСИ ---
list_proxies() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              СПИСОК ВСЕХ ПРОКСИ СЕРВЕРОВ                 ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local found=0
    
    # VLESS Reality
    echo -e "${YELLOW}▶ VLESS Reality прокси:${NC}"
    if ls "$CONFIG_DIR/reality/"*_info.txt 2>/dev/null | grep -q .; then
        for info_file in "$CONFIG_DIR/reality/"*_info.txt; do
            if [ -f "$info_file" ]; then
                local client=$(grep "Клиент:" "$info_file" | cut -d: -f2 | xargs)
                local port=$(grep "Порт:" "$info_file" | cut -d: -f2 | xargs)
                local link=$(grep -A1 "Ссылка для подключения:" "$info_file" | tail -n1)
                
                # Проверяем статус
                if systemctl is-active --quiet "xray-${client}"; then
                    local status="${GREEN}Активен${NC}"
                else
                    local status="${RED}Остановлен${NC}"
                fi
                
                echo -e "  ${GREEN}•${NC} ${CYAN}$client${NC} (порт: $port) - $status"
                echo -e "    ${BLUE}$link${NC}"
                echo ""
                found=1
            fi
        done
    else
        echo -e "  ${RED}Нет прокси${NC}"
        echo ""
    fi
    
    # Shadowsocks
    echo -e "${YELLOW}▶ Shadowsocks прокси:${NC}"
    if ls "$CONFIG_DIR/shadowsocks/"*_info.txt 2>/dev/null | grep -q .; then
        for info_file in "$CONFIG_DIR/shadowsocks/"*_info.txt; do
            if [ -f "$info_file" ]; then
                local client=$(grep "Клиент:" "$info_file" | cut -d: -f2 | xargs)
                local port=$(grep "Порт:" "$info_file" | cut -d: -f2 | xargs)
                local link=$(grep -A1 "Ссылка для подключения:" "$info_file" | tail -n1)
                
                # Проверяем статус
                if docker ps | grep -q "ss-${client}"; then
                    local status="${GREEN}Активен${NC}"
                else
                    local status="${RED}Остановлен${NC}"
                fi
                
                echo -e "  ${GREEN}•${NC} ${CYAN}$client${NC} (порт: $port) - $status"
                echo -e "    ${BLUE}$link${NC}"
                echo ""
                found=1
            fi
        done
    else
        echo -e "  ${RED}Нет прокси${NC}"
        echo ""
    fi
    
    if [ $found -eq 0 ]; then
        echo -e "${RED}Прокси не найдены. Создайте новый прокси.${NC}"
        echo ""
    fi
    
    read -p "Нажмите Enter для продолжения..."
}

# --- УДАЛЕНИЕ ПРОКСИ ---
delete_proxy() {
    clear
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                  УДАЛЕНИЕ ПРОКСИ                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Собираем все прокси
    local -a all_proxies
    local index=1
    
    # Reality
    if ls "$CONFIG_DIR/reality/"*_info.txt 2>/dev/null | grep -q .; then
        for info_file in "$CONFIG_DIR/reality/"*_info.txt; do
            local client=$(grep "Клиент:" "$info_file" | cut -d: -f2 | xargs)
            all_proxies[$index]="reality:$client"
            echo -e "${YELLOW}$index)${NC} VLESS Reality - $client"
            ((index++))
        done
    fi
    
    # Shadowsocks
    if ls "$CONFIG_DIR/shadowsocks/"*_info.txt 2>/dev/null | grep -q .; then
        for info_file in "$CONFIG_DIR/shadowsocks/"*_info.txt; do
            local client=$(grep "Клиент:" "$info_file" | cut -d: -f2 | xargs)
            all_proxies[$index]="shadowsocks:$client"
            echo -e "${YELLOW}$index)${NC} Shadowsocks - $client"
            ((index++))
        done
    fi
    
    if [ ${#all_proxies[@]} -eq 0 ]; then
        error "Нет прокси для удаления"
        read -p "Нажмите Enter..."
        return
    fi
    
    echo ""
    read -p "Выберите номер для удаления (0 для отмены): " choice
    
    if [ "$choice" = "0" ]; then
        return
    fi
    
    if [ -z "${all_proxies[$choice]}" ]; then
        error "Неверный выбор"
        read -p "Нажмите Enter..."
        return
    fi
    
    local proto=$(echo "${all_proxies[$choice]}" | cut -d: -f1)
    local client=$(echo "${all_proxies[$choice]}" | cut -d: -f2)
    
    echo ""
    read -p "Вы уверены, что хотите удалить '$client'? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        info "Отменено"
        read -p "Нажмите Enter..."
        return
    fi
    
    case $proto in
        reality)
            systemctl stop "xray-${client}" 2>/dev/null
            systemctl disable "xray-${client}" 2>/dev/null
            rm -f "/etc/systemd/system/xray-${client}.service"
            rm -f "$CONFIG_DIR/reality/${client}.json"
            rm -f "$CONFIG_DIR/reality/${client}_info.txt"
            systemctl daemon-reload
            success "VLESS Reality '$client' удален"
            ;;
        shadowsocks)
            docker stop "ss-${client}" 2>/dev/null
            docker rm "ss-${client}" 2>/dev/null
            rm -f "$CONFIG_DIR/shadowsocks/${client}_info.txt"
            success "Shadowsocks '$client' удален"
            ;;
    esac
    
    read -p "Нажмите Enter..."
}

# --- ПОЛНОЕ УДАЛЕНИЕ ---
full_uninstall() {
    clear
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║          ПОЛНОЕ УДАЛЕНИЕ ВСЕХ КОМПОНЕНТОВ              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Вы ДЕЙСТВИТЕЛЬНО хотите удалить ВСЁ? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        info "Отменено"
        return
    fi
    
    info "Остановка всех сервисов..."
    
    # Останавливаем все Xray сервисы
    for service in /etc/systemd/system/xray-*.service; do
        if [ -f "$service" ]; then
            local svc_name=$(basename "$service")
            systemctl stop "$svc_name" 2>/dev/null
            systemctl disable "$svc_name" 2>/dev/null
            rm -f "$service"
        fi
    done
    
    # Останавливаем все Shadowsocks контейнеры
    docker stop $(docker ps -aq --filter "name=ss-") 2>/dev/null
    docker rm $(docker ps -aq --filter "name=ss-") 2>/dev/null
    
    # Останавливаем 3X-UI
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    
    # Удаляем файлы
    rm -rf "$INSTALL_DIR"
    rm -rf /usr/local/x-ui
    rm -f /usr/local/bin/xray
    rm -f "/usr/local/bin/$SCRIPT_NAME"
    
    systemctl daemon-reload
    
    success "Всё удалено"
    exit 0
}

# --- МЕНЮ СОЗДАНИЯ ПРОКСИ ---
create_proxy_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              СОЗДАНИЕ НОВОГО ПРОКСИ                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Выберите протокол:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} VLESS + Reality     ${CYAN}(Рекомендуется - лучшая защита)${NC}"
    echo -e "  ${GREEN}2)${NC} Shadowsocks         ${CYAN}(Высокая скорость)${NC}"
    echo -e "  ${GREEN}0)${NC} Назад"
    echo ""
    
    read -p "Выбор: " protocol_choice
    
    case $protocol_choice in
        1)
            echo ""
            read -p "Введите имя клиента (например, client1): " client_name
            
            if [ -z "$client_name" ]; then
                error "Имя не может быть пустым"
                read -p "Нажмите Enter..."
                return
            fi
            
            # Проверяем существование
            if [ -f "$CONFIG_DIR/reality/${client_name}_info.txt" ]; then
                error "Клиент '$client_name' уже существует"
                read -p "Нажмите Enter..."
                return
            fi
            
            read -p "Введите порт (по умолчанию 443): " port
            port=${port:-443}
            
            # Проверяем порт
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                error "Неверный порт"
                read -p "Нажмите Enter..."
                return
            fi
            
            create_vless_reality "$client_name" "$port"
            read -p "Нажмите Enter..."
            ;;
        2)
            echo ""
            read -p "Введите имя клиента (например, client1): " client_name
            
            if [ -z "$client_name" ]; then
                error "Имя не может быть пустым"
                read -p "Нажмите Enter..."
                return
            fi
            
            # Проверяем существование
            if docker ps -a | grep -q "ss-${client_name}"; then
                error "Клиент '$client_name' уже существует"
                read -p "Нажмите Enter..."
                return
            fi
            
            read -p "Введите порт (по умолчанию 8388): " port
            port=${port:-8388}
            
            # Проверяем порт
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                error "Неверный порт"
                read -p "Нажмите Enter..."
                return
            fi
            
            create_shadowsocks "$client_name" "$port"
            read -p "Нажмите Enter..."
            ;;
        0)
            return
            ;;
        *)
            error "Неверный выбор"
            read -p "Нажмите Enter..."
            ;;
    esac
}

# --- ГЛАВНОЕ МЕНЮ ---
main_menu() {
    while true; do
        clear
        show_banner
        
        local server_ip=$(get_server_ip)
        
        echo -e "${CYAN}Сервер:${NC} $server_ip"
        echo -e "${CYAN}3X-UI Панель:${NC} http://$server_ip:54321 (admin/admin)"
        echo ""
        echo -e "${BOLD}ГЛАВНОЕ МЕНЮ${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Создать новый прокси"
        echo -e "  ${GREEN}2)${NC} Показать список прокси"
        echo -e "  ${GREEN}3)${NC} Удалить прокси"
        echo -e "  ${GREEN}4)${NC} Статус сервисов"
        echo -e "  ${GREEN}5)${NC} Открыть 3X-UI панель (инфо)"
        echo -e "  ${RED}9)${NC} Полное удаление"
        echo -e "  ${GREEN}0)${NC} Выход"
        echo ""
        
        read -p "Выберите пункт: " choice
        
        case $choice in
            1)
                create_proxy_menu
                ;;
            2)
                list_proxies
                ;;
            3)
                delete_proxy
                ;;
            4)
                clear
                echo -e "${CYAN}═══ Статус Xray сервисов ═══${NC}"
                systemctl status xray-* --no-pager 2>/dev/null || echo "Нет Xray сервисов"
                echo ""
                echo -e "${CYAN}═══ Статус Docker контейнеров ═══${NC}"
                docker ps -a --filter "name=ss-" 2>/dev/null || echo "Нет SS контейнеров"
                echo ""
                echo -e "${CYAN}═══ Статус 3X-UI ═══${NC}"
                systemctl status x-ui --no-pager 2>/dev/null || echo "3X-UI не установлена"
                echo ""
                read -p "Нажмите Enter..."
                ;;
            5)
                clear
                echo -e "${GREEN}═════════════════════════════════════════${NC}"
                echo -e "${CYAN}3X-UI Веб-панель${NC}"
                echo -e "${GREEN}═════════════════════════════════════════${NC}"
                echo -e "${YELLOW}URL:${NC} http://$server_ip:54321"
                echo -e "${YELLOW}Логин:${NC} admin"
                echo -e "${YELLOW}Пароль:${NC} admin"
                echo ""
                echo -e "${CYAN}В панели можно:${NC}"
                echo -e "  • Создавать VLESS, VMess, Trojan прокси"
                echo -e "  • Управлять пользователями"
                echo -e "  • Смотреть статистику трафика"
                echo -e "  • Экспортировать конфигурации"
                echo -e "${GREEN}═════════════════════════════════════════${NC}"
                echo ""
                read -p "Нажмите Enter..."
                ;;
            9)
                full_uninstall
                ;;
            0)
                exit 0
                ;;
            *)
                error "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# --- ОСНОВНАЯ УСТАНОВКА ---
main_install() {
    show_banner
    
    info "Начинаем установку..."
    echo ""
    
    check_root
    detect_os
    
    # Обновляем систему
    update_system
    
    # Устанавливаем зависимости (включая unzip!)
    install_dependencies
    
    # Создаем структуру директорий
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"/{reality,shadowsocks}
    mkdir -p /var/log/xray
    
    # Устанавливаем компоненты
    install_docker
    install_xray
    install_shadowsocks
    
    # Устанавливаем 3X-UI панель
    install_3xui
    
    # Копируем скрипт
    cp "$0" "/usr/local/bin/$SCRIPT_NAME"
    chmod +x "/usr/local/bin/$SCRIPT_NAME"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Команда для запуска:${NC} ${YELLOW}$SCRIPT_NAME${NC}"
    echo -e "${CYAN}3X-UI Панель:${NC} ${YELLOW}http://$(get_server_ip):54321${NC}"
    echo -e "${CYAN}Логин/Пароль:${NC} ${YELLOW}admin/admin${NC}"
    echo ""
    echo -e "${YELLOW}Нажмите Enter для перехода в меню...${NC}"
    read
    
    main_menu
}

# --- ТОЧКА ВХОДА ---
if [ ! -f "/usr/local/bin/$SCRIPT_NAME" ] || [ ! -d "$INSTALL_DIR" ]; then
    main_install
else
    main_menu
fi
