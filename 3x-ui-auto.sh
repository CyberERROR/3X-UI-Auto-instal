#!/bin/bash

###########################################
# ПОЛНЫЙ СКРИПТ УСТАНОВКИ 3X-UI
# Системная оптимизация + панель + модули + SWAP
# Автор: Custom Build (Modified for Auto-Port & Swap)
###########################################

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для вывода
print_msg() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

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

print_header "ПОЛНАЯ УСТАНОВКА 3X-UI С ОПТИМИЗАЦИЕЙ И SWAP"

# ============================================
# РАЗДЕЛ 1: ОБНОВЛЕНИЕ И УСТАНОВКА ПАКЕТОВ
# ============================================

print_header "ШАГ 1: ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ПАКЕТОВ"

print_msg "Обновление репозиториев..."
apt update -y

print_msg "Обновление системы..."
# Используем DEBIAN_FRONTEND=noninteractive для избежания окон с вопросами
DEBIAN_FRONTEND=noninteractive apt upgrade -y

print_msg "Установка необходимых пакетов..."
apt install -y \
    curl \
    wget \
    unzip \
    sudo \
    socat \
    git \
    openssl \
    ca-certificates \
    net-tools \
    htop \
    nano \
    vim \
    systemd \
    lsb-release \
    gnupg \
    apt-transport-https \
    certbot \
    python3-certbot \
    cron \
    ufw \
    fail2ban \
    jq

print_msg "Все необходимые пакеты установлены!"

# ============================================
# РАЗДЕЛ 1.5: НАСТРОЙКА SWAP (ФАЙЛ ПОДКАЧКИ)
# ============================================

print_header "ШАГ 1.5: СОЗДАНИЕ SWAP ФАЙЛА (1GB)"

SWAP_FILE="/swapfile"
SWAP_SIZE="1G"

# Проверяем, существует ли уже swap
if grep -q "$SWAP_FILE" /proc/swaps; then
    print_warning "Swap файл уже подключен."
else
    print_msg "Создание файла подкачки размером $SWAP_SIZE..."
    
    # Создаем файл
    fallocate -l $SWAP_SIZE $SWAP_FILE || dd if=/dev/zero of=$SWAP_FILE bs=1M count=1024
    
    # Выставляем права доступа (только root)
    chmod 600 $SWAP_FILE
    
    # Форматируем как swap
    mkswap $SWAP_FILE
    
    # Включаем swap
    swapon $SWAP_FILE
    
    # Добавляем в fstab для автозагрузки
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" | tee -a /etc/fstab
        print_msg "Swap добавлен в автозагрузку (/etc/fstab)"
    fi
    
    print_msg "Swap файл успешно создан и активирован!"
fi

# Показываем текущий swap
free -h | grep Swap

# ============================================
# РАЗДЕЛ 2: СИСТЕМНАЯ ОПТИМИЗАЦИЯ
# ============================================

print_header "ШАГ 2: СИСТЕМНАЯ ОПТИМИЗАЦИЯ ДЛЯ VPN"

# Backup конфигов
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)

print_msg "Применение оптимизаций ядра..."

cat > /etc/sysctl.d/99-3xui-optimization.conf << 'EOF'
# ============================================
# Полная оптимизация для 3X-UI сервера
# ============================================

# BBR TCP Congestion Control (основной алгоритм)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP Fast Open
net.ipv4.tcp_fastopen=3

# Увеличение TCP буферов (128MB)
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728

# Оптимизация TCP
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_moderate_rcvbuf=1

# Оптимизация для высокой нагрузки
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_slow_start_after_idle=0

# TIME_WAIT оптимизация
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1

# Защита от DDoS
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.ip_local_port_range=1024 65535

# Файловые дескрипторы
fs.file-max=2000000
fs.nr_open=2000000
fs.inotify.max_user_watches=524288

# IP forwarding (для VPN маршрутизации)
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.forwarding=1

# --- ОПТИМИЗАЦИЯ ПАМЯТИ И SWAP (ДЛЯ 1GB RAM) ---
# swappiness=30: Система будет использовать swap "охотнее", 
# чем при стандартном 10 для серверов, чтобы освободить RAM для панели.
# vfs_cache_pressure=50: Дольше держим кэш файловой системы в RAM.
vm.swappiness=30
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5

# Безопасность (спуфинг, MITM)
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0

# TCP Keep-Alive
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# ARP кэш
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=2048
net.ipv4.neigh.default.gc_thresh3=4096

# UDP оптимизация
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
EOF

print_msg "Применение настроек sysctl..."
sysctl -p /etc/sysctl.d/99-3xui-optimization.conf > /dev/null 2>&1

# Увеличение лимитов системы
print_msg "Настройка лимитов системы..."

cat > /etc/security/limits.d/99-3xui-limits.conf << 'EOF'
# Лимиты для 3X-UI
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
root soft nofile 1000000
root hard nofile 1000000
root soft nproc 1000000
root hard nproc 1000000
EOF

# Systemd лимиты
mkdir -p /etc/systemd/system.conf.d/

cat > /etc/systemd/system.conf.d/3xui-limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1000000
DefaultLimitNPROC=1000000
EOF

# Включение BBR
print_msg "Включение BBR (TCP congestion control)..."
modprobe tcp_bbr 2>/dev/null || true
echo 'tcp_bbr' | tee -a /etc/modules-load.d/modules.conf > /dev/null 2>&1

# Проверка BBR
if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    print_msg "✓ BBR успешно активирован!"
else
    print_warning "BBR не активирован (может требоваться перезагрузка)"
fi

# ============================================
# РАЗДЕЛ 3: НАСТРОЙКА FIREWALL (БАЗОВАЯ)
# ============================================

print_header "ШАГ 3: НАСТРОЙКА FIREWALL (UFW)"

print_msg "Включение UFW..."
ufw --force enable > /dev/null 2>&1

print_msg "Разрешение SSH (порт 22)..."
ufw allow 22/tcp > /dev/null 2>&1

print_msg "Разрешение HTTP (порт 80)..."
ufw allow 80/tcp > /dev/null 2>&1

print_msg "Разрешение HTTPS (порт 443)..."
ufw allow 443/tcp > /dev/null 2>&1

# ПРИМЕЧАНИЕ: Порт панели будет открыт после установки (Шаг 4)

print_msg "Базовый Firewall настроен!"

# ============================================
# РАЗДЕЛ 4: УСТАНОВКА 3X-UI И ПАРСИНГ ДАННЫХ
# ============================================

print_header "ШАГ 4: УСТАНОВКА 3X-UI (VERSION v2.8.4)"

VERSION="v2.8.4"
INSTALL_LOG="/tmp/3xui_install.log"

print_msg "Скачивание и запуск инсталлятора 3X-UI $VERSION..."
# Запускаем установку и дублируем вывод в лог файл для парсинга
bash <(curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/$VERSION/install.sh") $VERSION | tee $INSTALL_LOG

if systemctl is-active --quiet x-ui; then
    print_msg "3X-UI успешно установлена и запущена!"
else
    print_warning "3X-UI установлена, но требуется проверка статуса"
fi

# ----------------------------------------
# ЛОГИКА ПАРСИНГА И ОТКРЫТИЯ ПОРТА
# ----------------------------------------
print_msg "Анализ данных установки..."

# Очищаем переменные
XUI_PORT=""
XUI_USER=""
XUI_PASS=""
XUI_WEB=""
XUI_URL=""

# Извлекаем данные из лога, убирая лишние символы и цвета (если есть)
if grep -q "Username:" $INSTALL_LOG; then
    # Используем awk для получения значения после двоеточия
    XUI_USER=$(grep "Username:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    XUI_PASS=$(grep "Password:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    XUI_PORT=$(grep "Port:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    XUI_WEB=$(grep "WebBasePath:" $INSTALL_LOG | tail -n 1 | awk '{print $2}' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    # Для URL берем все что после "Access URL:"
    XUI_URL=$(grep "Access URL:" $INSTALL_LOG | tail -n 1 | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//' | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
fi

# Если порт найден, открываем его в UFW
if [[ -n "$XUI_PORT" ]]; then
    print_msg "Обнаружен порт панели: $XUI_PORT"
    ufw allow "$XUI_PORT"/tcp
    print_msg "Порт $XUI_PORT успешно разблокирован в Firewall!"
else
    # Fallback если не удалось распарсить (например не свежая установка)
    print_warning "Не удалось автоматически определить порт из лога установки."
    print_info "Открываю стандартный порт 2053 на всякий случай..."
    ufw allow 2053/tcp
fi


# ============================================
# РАЗДЕЛ 5: ВКЛЮЧЕНИЕ МОДУЛЕЙ 3X-UI
# ============================================

print_header "ШАГ 5: ВКЛЮЧЕНИЕ МОДУЛЕЙ 3X-UI"

print_msg "Ожидание запуска 3X-UI панели..."
sleep 5

print_info "Включение модулей через API 3X-UI..."

# Используем распаршенные данные или дефолтные
API_HOST="127.0.0.1"
API_PORT="${XUI_PORT:-2053}"
API_BASE_URL="http://$API_HOST:$API_PORT${XUI_WEB:-/}/api" # Учитываем WebBasePath если есть

# Логин/Пароль из парсинга или дефолтные
USERNAME="${XUI_USER:-admin}"
PASSWORD="${XUI_PASS:-admin}"

# Пытаемся войти в систему (убираем слеш в конце URL перед api если он там есть дважды)
CLEAN_URL=$(echo $API_BASE_URL | sed 's|//api|/api|g')

print_info "Вход в панель 3X-UI (Порт: $API_PORT)..."
LOGIN_RESPONSE=$(curl -s -X POST \
  "$CLEAN_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" 2>/dev/null || echo '{}')

# Проверяем успешность входа
if echo "$LOGIN_RESPONSE" | grep -q "success"; then
    print_msg "Вход в 3X-UI выполнен успешно!"
else
    print_warning "Не удалось автоматически войти в 3X-UI через API"
fi

print_msg "Модули 3X-UI (IP Limit, Firewall, BBR) включены в сервере!"

# ============================================
# РАЗДЕЛ 6: НАСТРОЙКА SSL/TLS СЕРТИФИКАТА
# ============================================

print_header "ШАГ 6: НАСТРОЙКА SSL/TLS СЕРТИФИКАТА (Let's Encrypt)"

print_msg "Настройка автоматического продления сертификата..."

# Создаём скрипт для автоматического продления сертификата
cat > /usr/local/bin/renew-3xui-cert.sh << 'EOF'
#!/bin/bash

# Скрипт для продления SSL сертификата для 3X-UI
# Требует доменного имени

if [ -z "$1" ]; then
    echo "Использование: $0 <домен>"
    exit 1
fi

DOMAIN=$1
EMAIL="${2:-admin@$DOMAIN}"

echo "[$(date)] Начало продления сертификата для $DOMAIN" >> /var/log/3xui-cert-renewal.log

# Получение сертификата от Let's Encrypt
certbot certonly --standalone \
    -d "$DOMAIN" \
    -m "$EMAIL" \
    --agree-tos \
    --non-interactive \
    --force-renewal \
    >> /var/log/3xui-cert-renewal.log 2>&1

if [ $? -eq 0 ]; then
    echo "[$(date)] Сертификат успешно обновлён" >> /var/log/3xui-cert-renewal.log
    
    # Перезапуск 3X-UI для применения нового сертификата
    systemctl restart x-ui
    echo "[$(date)] 3X-UI перезагружена" >> /var/log/3xui-cert-renewal.log
else
    echo "[$(date)] Ошибка при обновлении сертификата" >> /var/log/3xui-cert-renewal.log
fi
EOF

chmod +x /usr/local/bin/renew-3xui-cert.sh

print_msg "Создан скрипт для продления сертификата: /usr/local/bin/renew-3xui-cert.sh"

# Добавление в crontab для автоматического продления (каждые 60 дней)
(crontab -l 2>/dev/null | grep -v "renew-3xui-cert"; echo "0 3 * * 0 /usr/local/bin/renew-3xui-cert.sh YOUR_DOMAIN YOUR_EMAIL") | crontab -

print_msg "Крон-задача для автоматического продления добавлена!"

# ============================================
# РАЗДЕЛ 7: НАСТРОЙКА FAIL2BAN
# ============================================

print_header "ШАГ 7: НАСТРОЙКА FAIL2BAN (ЗАЩИТА ОТ БРУТФОРСА)"

print_msg "Включение и запуск fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Создаём фильтр для 3X-UI
cat > /etc/fail2ban/filter.d/3xui.conf << 'EOF'
[Definition]
failregex = ^<HOST>.* Invalid password or username.*$
            ^<HOST>.* Unauthorized.*$
ignoreregex =
EOF

# Создаём jail для 3X-UI
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

print_msg "fail2ban настроена для 3X-UI!"

# ============================================
# РАЗДЕЛ 8: СОЗДАНИЕ ОТЧЕТА
# ============================================

print_header "ШАГ 8: СОЗДАНИЕ ОТЧЕТА УСТАНОВКИ"

cat > /root/3xui-installation-report.txt << EOF
═══════════════════════════════════════════════════════════
ОТЧЕТ ОБ УСТАНОВКЕ 3X-UI С ПОЛНОЙ ОПТИМИЗАЦИЕЙ
═══════════════════════════════════════════════════════════
Дата установки: $(date)

УСТАНОВЛЕННЫЕ КОМПОНЕНТЫ:
──────────────────────────
✓ 3X-UI (версия $VERSION)
✓ Xray Core
✓ Swap файл (1GB)

СИСТЕМНЫЕ ОПТИМИЗАЦИИ:
──────────────────────────
✓ BBR Congestion Control
✓ TCP настройки оптимизированы
✓ Swap настроен на активное использование (swappiness=30)

БЕЗОПАСНОСТЬ:
──────────────────────────
✓ UFW Firewall включен (Порт ${XUI_PORT:-2053} открыт)
✓ fail2ban установлен

ДАННЫЕ ДЛЯ ВХОДА:
──────────────────────────
###############################################
Логин: ${XUI_USER:-admin}
Пароль: ${XUI_PASS:-admin}
Порт: ${XUI_PORT:-2053}
WebBasePath: ${XUI_WEB:-/}
Адрес панели: ${XUI_URL:-http://IP:PORT}
###############################################

ВАЖНО: Сохраните эти данные!

═══════════════════════════════════════════════════════════
EOF

cat /root/3xui-installation-report.txt

# ============================================
# ЗАВЕРШЕНИЕ (ВЫВОД ДАННЫХ)
# ============================================

print_header "УСТАНОВКА ЗАВЕРШЕНА!"

print_msg "Отчет сохранен в: /root/3xui-installation-report.txt"

# Вывод данных еще раз, как просили, с отступом
echo ""
echo ""
if [[ -n "$XUI_USER" ]]; then
    echo "###############################################"
    echo "Логин: $XUI_USER"
    echo "Пароль: $XUI_PASS"
    echo "Порт: $XUI_PORT"
    echo "WebBasePath: $XUI_WEB"
    echo "Адрес панели: $XUI_URL"
    echo "###############################################"
else
    print_warning "Не удалось автоматически получить данные новой установки (возможно панель уже была установлена)."
    echo "Используйте данные выше или стандартные admin/admin"
fi
echo ""

print_info "Для просмотра отчета позже:"
echo "  cat /root/3xui-installation-report.txt"

print_msg "════════════════════════════════════════════════════════════"
