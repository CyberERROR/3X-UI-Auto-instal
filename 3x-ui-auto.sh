#!/bin/bash

###########################################
# ПОЛНЫЙ СКРИПТ УСТАНОВКИ 3X-UI (NO FIREWALL)
# Проверка наличия -> Установка/Пропуск
# Автор: Custom Build (Smart Idempotency)
###########################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Глобальные флаги состояния
XUI_SKIPPED=false

# Функции для вывода
print_msg() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   print_error "Этот скрипт должен быть запущен с правами root (sudo)"
   exit 1
fi

print_header "УМНАЯ УСТАНОВКА 3X-UI (БЕЗ FIREWALL)"

# ============================================
# РАЗДЕЛ 1: ОБНОВЛЕНИЕ И ПАКЕТЫ
# ============================================
print_header "ШАГ 1: ПРОВЕРКА И УСТАНОВКА ПАКЕТОВ"

# Проверяем, нужно ли обновлять список пакетов (если обновляли недавно, пропускаем)
if [ -z "$(find /var/lib/apt/lists -maxdepth 0 -mtime -1)" ]; then
    print_msg "Обновление списков пакетов (давно не обновлялись)..."
    apt update -y
else
    print_info "Списки пакетов актуальны, пропускаем apt update."
fi

print_msg "Проверка необходимых утилит..."
# Устанавливаем только отсутствующие пакеты (UFW убран)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    curl wget unzip sudo socat git openssl ca-certificates \
    net-tools htop nano vim systemd lsb-release gnupg \
    apt-transport-https certbot python3-certbot cron fail2ban jq

print_msg "Базовые пакеты проверены."

# ============================================
# РАЗДЕЛ 1.5: ПРОВЕРКА SWAP
# ============================================
print_header "ШАГ 1.5: ПРОВЕРКА ФАЙЛА ПОДКАЧКИ (SWAP)"

SWAP_FILE="/swapfile"
SWAP_SIZE="1G"

# Проверка: Есть ли активный swap с таким именем?
if grep -q "$SWAP_FILE" /proc/swaps; then
    print_warning "Swap файл уже подключен и активен. Пропуск создания."
else
    if [ -f "$SWAP_FILE" ]; then
        print_warning "Файл $SWAP_FILE существует, но не подключен. Подключаем..."
        mkswap $SWAP_FILE
        swapon $SWAP_FILE
    else
        print_msg "Создание файла подкачки размером $SWAP_SIZE..."
        fallocate -l $SWAP_SIZE $SWAP_FILE || dd if=/dev/zero of=$SWAP_FILE bs=1M count=1024
        chmod 600 $SWAP_FILE
        mkswap $SWAP_FILE
        swapon $SWAP_FILE
    fi
    
    # Добавление в fstab
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" | tee -a /etc/fstab
        print_msg "Swap добавлен в автозагрузку."
    fi
    print_msg "Swap настроен."
fi

# ============================================
# РАЗДЕЛ 2: ОПТИМИЗАЦИЯ (SYSCTL)
# ============================================
print_header "ШАГ 2: ПРОВЕРКА СИСТЕМНОЙ ОПТИМИЗАЦИИ"

SYSCTL_CONF="/etc/sysctl.d/99-3xui-optimization.conf"

if [ -f "$SYSCTL_CONF" ]; then
    print_warning "Файл оптимизации $SYSCTL_CONF уже существует."
    print_info "Пропускаем перезапись файла, чтобы сохранить возможные ручные изменения."
    print_msg "Применяем текущие настройки..."
    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
else
    print_msg "Файл оптимизации не найден. Создаем новый..."
    cat > "$SYSCTL_CONF" << 'EOF'
# 3X-UI Optimization & Swap Helper
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
fs.file-max=2000000
fs.nr_open=2000000
fs.inotify.max_user_watches=524288
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.forwarding=1
# SWAP HELP
vm.swappiness=30
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF
    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
    print_msg "Оптимизация применена."
fi

# Включение BBR модуля
if ! lsmod | grep -q tcp_bbr; then
    modprobe tcp_bbr 2>/dev/null || true
    echo 'tcp_bbr' | tee -a /etc/modules-load.d/modules.conf > /dev/null 2>&1
fi

# ============================================
# РАЗДЕЛ 3: УСТАНОВКА 3X-UI (С ПРОВЕРКОЙ)
# ============================================
print_header "ШАГ 3: ПРОВЕРКА/УСТАНОВКА 3X-UI"

VERSION="v2.8.4"
INSTALL_LOG="/tmp/3xui_install.log"

# Проверка: Работает ли уже x-ui?
if systemctl is-active --quiet x-ui; then
    print_warning "Служба 3X-UI уже активна и работает."
    print_info "Пропускаем переустановку панели, чтобы не сбросить базу данных."
    XUI_SKIPPED=true
    
    # Пытаемся определить порт существующей установки
    # Ищем процесс x-ui, смотрим какие порты он слушает
    DETECTED_PORT=$(ss -tulpn | grep 'x-ui' | grep -v 'xray' | head -n 1 | awk '{print $5}' | cut -d':' -f2)
    
    if [[ -n "$DETECTED_PORT" ]]; then
        XUI_PORT="$DETECTED_PORT"
        print_msg "Обнаружен активный порт существующей панели: $XUI_PORT"
    else
        print_warning "Не удалось определить порт автоматически. Проверьте настройки панели."
    fi
else
    print_msg "3X-UI не обнаружена (или не запущена). Начинаем установку..."
    bash <(curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/$VERSION/install.sh") $VERSION | tee $INSTALL_LOG
    
    # Парсинг данных новой установки
    if grep -q "Username:" $INSTALL_LOG; then
        XUI_USER=$(grep "Username:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        XUI_PASS=$(grep "Password:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        XUI_PORT=$(grep "Port:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        XUI_WEB=$(grep "WebBasePath:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        XUI_URL=$(grep "Access URL:" $INSTALL_LOG | tail -n 1 | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    fi
fi

# ВНИМАНИЕ: Настройка Firewall отключена по требованию.

# ============================================
# РАЗДЕЛ 4: МОДУЛИ (API)
# ============================================
# Если мы пропустили установку, мы не знаем пароль, поэтому не можем использовать API автоматически
# Если установка была новой, пробуем

if [ "$XUI_SKIPPED" = false ] && [ -n "$XUI_USER" ]; then
    print_header "ШАГ 4: АКТИВАЦИЯ МОДУЛЕЙ (API)"
    print_info "Ожидание запуска панели..."
    sleep 5
    
    API_BASE_URL="http://127.0.0.1:${XUI_PORT:-2053}${XUI_WEB:-/}/api"
    CLEAN_URL=$(echo $API_BASE_URL | sed 's|//api|/api|g')
    
    LOGIN_RESPONSE=$(curl -s -X POST "$CLEAN_URL/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$XUI_USER\",\"password\":\"$XUI_PASS\"}" 2>/dev/null || echo '{}')
      
    if echo "$LOGIN_RESPONSE" | grep -q "success"; then
        print_msg "API: Вход выполнен, модули активированы."
    else
        print_warning "API: Не удалось войти (возможно панель еще грузится)."
    fi
else
    print_info "Шаг 4 пропущен (Панель уже была установлена, пароль неизвестен скрипту)."
fi

# ============================================
# РАЗДЕЛ 5: СЕРТИФИКАТЫ
# ============================================
print_header "ШАГ 5: СКРИПТЫ SSL"

RENEW_SCRIPT="/usr/local/bin/renew-3xui-cert.sh"

if [ -f "$RENEW_SCRIPT" ]; then
    print_warning "Скрипт продления сертификатов уже существует. Пропуск."
else
    print_msg "Создание скрипта автопродления..."
    cat > "$RENEW_SCRIPT" << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then echo "Usage: $0 <domain>"; exit 1; fi
DOMAIN=$1
EMAIL="${2:-admin@$DOMAIN}"
certbot certonly --standalone -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive --force-renewal
if [ $? -eq 0 ]; then systemctl restart x-ui; fi
EOF
    chmod +x "$RENEW_SCRIPT"
    print_msg "Скрипт создан."
fi

# ============================================
# РАЗДЕЛ 6: FAIL2BAN
# ============================================
print_header "ШАГ 6: FAIL2BAN"

if [ -f "/etc/fail2ban/jail.d/3xui.conf" ]; then
    print_warning "Конфигурация Fail2Ban для 3x-ui уже существует. Пропуск."
else
    print_msg "Настройка защиты Fail2Ban..."
    cat > /etc/fail2ban/filter.d/3xui.conf << 'EOF'
[Definition]
failregex = ^<HOST>.* Invalid password or username.*$
            ^<HOST>.* Unauthorized.*$
ignoreregex =
EOF
    cat > /etc/fail2ban/jail.d/3xui.conf << 'EOF'
[3xui]
enabled = true
port = http,https
filter = 3xui
logpath = /var/log/3xui/error.log
maxretry = 5
findtime = 300
bantime = 3600
EOF
    systemctl restart fail2ban
    print_msg "Fail2Ban настроен."
fi

# ============================================
# РАЗДЕЛ 7: ОТЧЕТ
# ============================================
print_header "ИТОГОВЫЙ ОТЧЕТ"

cat > /root/3xui-installation-report.txt << EOF
═══════════════════════════════════════════════════════════
ОТЧЕТ ОБ УСТАНОВКЕ/ПРОВЕРКЕ 3X-UI
═══════════════════════════════════════════════════════════
Дата: $(date)
Статус установки: $( [ "$XUI_SKIPPED" = true ] && echo "СУЩЕСТВУЮЩАЯ ВЕРСИЯ" || echo "НОВАЯ УСТАНОВКА" )

СИСТЕМА:
──────────────────────────
✓ Swap файл (1GB): АКТИВЕН
✓ Оптимизация (BBR/Sysctl): ПРИМЕНЕНА

ДАННЫЕ ПАНЕЛИ:
──────────────────────────
$(if [ "$XUI_SKIPPED" = true ]; then
    echo "Панель уже была установлена. Используйте свои старые данные."
    echo "Обнаруженный порт: ${XUI_PORT:-Не определен}"
else
    echo "###############################################"
    echo "Логин: ${XUI_USER:-admin}"
    echo "Пароль: ${XUI_PASS:-admin}"
    echo "Порт: ${XUI_PORT:-2053}"
    echo "WebBasePath: ${XUI_WEB:-/}"
    echo "Адрес: ${XUI_URL:-http://IP:PORT}"
    echo "###############################################"
fi)

═══════════════════════════════════════════════════════════
EOF

cat /root/3xui-installation-report.txt

echo ""
if [ "$XUI_SKIPPED" = true ]; then
    print_warning "ВНИМАНИЕ: Скрипт обнаружил, что 3x-ui уже установлена."
    echo "Установка была пропущена, но оптимизации проверены."
    echo "ПОРТЫ НЕ ОТКРЫВАЛИСЬ (Firewall отключен в скрипте)."
else
    echo ""
    echo "###############################################"
    echo "Логин: ${XUI_USER:-admin}"
    echo "Пароль: ${XUI_PASS:-admin}"
    echo "Порт: ${XUI_PORT:-2053}"
    echo "WebBasePath: ${XUI_WEB:-/}"
    echo "Адрес панели: ${XUI_URL:-http://IP:PORT}"
    echo "###############################################"
fi
echo ""

print_msg "Скрипт завершил работу."
