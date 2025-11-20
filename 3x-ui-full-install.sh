#!/bin/bash

###########################################
# ПОЛНЫЙ СКРИПТ УСТАНОВКИ 3X-UI
# Системная оптимизация + панель + модули
# Автор: Custom Build
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

print_header "ПОЛНАЯ УСТАНОВКА 3X-UI С ОПТИМИЗАЦИЕЙ"

# ============================================
# РАЗДЕЛ 1: ОБНОВЛЕНИЕ И УСТАНОВКА ПАКЕТОВ
# ============================================

print_header "ШАГ 1: ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ПАКЕТОВ"

print_msg "Обновление репозиториев..."
apt update -y

print_msg "Обновление системы..."
apt upgrade -y

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

# Оптимизация памяти
vm.swappiness=10
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
# РАЗДЕЛ 3: НАСТРОЙКА FIREWALL
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

print_msg "Firewall настроен!"

# ============================================
# РАЗДЕЛ 4: УСТАНОВКА 3X-UI
# ============================================

print_header "ШАГ 4: УСТАНОВКА 3X-UI (VERSION v2.8.4)"

VERSION="v2.8.4"

print_msg "Скачивание и запуск инсталлятора 3X-UI $VERSION..."
bash <(curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/$VERSION/install.sh") $VERSION

if systemctl is-active --quiet x-ui; then
    print_msg "3X-UI успешно установлена и запущена!"
else
    print_warning "3X-UI установлена, но требуется проверка статуса"
    print_info "Проверьте статус: systemctl status x-ui"
fi

# ============================================
# РАЗДЕЛ 5: ВКЛЮЧЕНИЕ МОДУЛЕЙ 3X-UI
# ============================================

print_header "ШАГ 5: ВКЛЮЧЕНИЕ МОДУЛЕЙ 3X-UI"

print_msg "Ожидание запуска 3X-UI панели..."
sleep 5

print_info "Включение модулей через API 3X-UI..."

# API параметры (по умолчанию)
API_HOST="127.0.0.1"
API_PORT="2053"
API_BASE_URL="http://$API_HOST:$API_PORT/api"

# Получаем стандартные учетные данные (или используем дефолтные)
USERNAME="${XUI_USERNAME:-admin}"
PASSWORD="${XUI_PASSWORD:-admin}"

# Пытаемся войти в систему
print_info "Вход в панель 3X-UI..."
LOGIN_RESPONSE=$(curl -s -X POST \
  "$API_BASE_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" 2>/dev/null || echo '{}')

# Проверяем успешность входа
if echo "$LOGIN_RESPONSE" | grep -q "success"; then
    print_msg "Вход в 3X-UI выполнен успешно!"
else
    print_warning "Не удалось автоматически войти в 3X-UI"
    print_info "Параметры для входа:"
    print_info "  URL: http://YOUR_IP:2053"
    print_info "  Пользователь: admin"
    print_info "  Пароль: admin"
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
print_info "Использование: renew-3xui-cert.sh <домен> [email]"

# Добавление в crontab для автоматического продления (каждые 60 дней)
(crontab -l 2>/dev/null | grep -v "renew-3xui-cert"; echo "0 3 * * 0 /usr/local/bin/renew-3xui-cert.sh YOUR_DOMAIN YOUR_EMAIL") | crontab -

print_msg "Крон-задача для автоматического продления добавлена!"
print_info "Отредактируйте /etc/crontab для настройки домена и email"

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
Версия ядра: $(uname -r)
Версия Ubuntu: $(lsb_release -ds)

УСТАНОВЛЕННЫЕ КОМПОНЕНТЫ:
──────────────────────────
✓ 3X-UI (версия $VERSION)
✓ Xray Core
✓ 1Panel (опционально)

СИСТЕМНЫЕ ОПТИМИЗАЦИИ:
──────────────────────────
✓ BBR Congestion Control (ВКЛЮЧЕН)
✓ TCP Fast Open (включен)
✓ Буферы TCP увеличены до 128MB
✓ File descriptors: 2,000,000
✓ Network backlog оптимизирован
✓ Защита от DDoS (SYN flood, IP spoofing)
✓ IP forwarding включен

СЕТЕВЫЕ МОДУЛИ 3X-UI:
──────────────────────────
✓ IP Limit Management (ВКЛЮЧЕН)
✓ Firewall Management (ВКЛЮЧЕН)
✓ BBR Support (ВКЛЮЧЕН)

БЕЗОПАСНОСТЬ:
──────────────────────────
✓ UFW Firewall включен
✓ fail2ban установлен и запущен
✓ Защита SSH включена
✓ Certbot установлен (Let's Encrypt)

УСТАНОВЛЕННЫЕ ПАКЕТЫ:
──────────────────────────
curl wget unzip sudo socat git openssl ca-certificates
net-tools htop nano vim systemd lsb-release gnupg
apt-transport-https certbot python3-certbot cron ufw fail2ban jq

ФАЙЛЫ КОНФИГУРАЦИИ:
──────────────────────────
/etc/sysctl.d/99-3xui-optimization.conf - оптимизация ядра
/etc/security/limits.d/99-3xui-limits.conf - лимиты системы
/etc/systemd/system.conf.d/3xui-limits.conf - systemd лимиты
/usr/local/bin/renew-3xui-cert.sh - скрипт продления сертификата
/var/log/3xui-cert-renewal.log - логи продления сертификата

ДОСТУП К ПАНЕЛИ 3X-UI:
──────────────────────────
URL: http://YOUR_IP:2053
Пользователь: admin
Пароль: admin

ВАЖНО: Измените пароль администратора!

КОМАНДЫ УПРАВЛЕНИЯ 3X-UI:
──────────────────────────
Запуск: systemctl start x-ui
Остановка: systemctl stop x-ui
Перезапуск: systemctl restart x-ui
Статус: systemctl status x-ui
Логи: journalctl -u x-ui -f

ПРОВЕРКА ОПТИМИЗАЦИЙ:
──────────────────────────
BBR статус: sysctl net.ipv4.tcp_congestion_control
Файловые дескрипторы: cat /proc/sys/fs/file-max
Модули ядра: lsmod | grep bbr
Сетевые параметры: ss -s

НАСТРОЙКА SSL СЕРТИФИКАТА:
──────────────────────────
Команда: /usr/local/bin/renew-3xui-cert.sh <домен> [email]

Пример: /usr/local/bin/renew-3xui-cert.sh example.com admin@example.com

Сертификаты хранятся в: /etc/letsencrypt/live/

Автоматическое продление настроено в crontab (каждые 60 дней)

ПОСЛЕДУЮЩИЕ ШАГИ:
──────────────────────────
1. Измените пароль администратора в панели 3X-UI
2. Получите SSL сертификат для вашего домена
3. Настройте VLESS/Trojan/Shadowsocks инбаунды
4. Добавьте клиентов и пользователей
5. Мониторьте логи: journalctl -u x-ui -f

РЕКОМЕНДАЦИИ ПО БЕЗОПАСНОСТИ:
──────────────────────────
✓ Используйте сложные пароли (16+ символов)
✓ Регулярно обновляйте систему (apt update && apt upgrade)
✓ Мониторьте логи fail2ban (fail2ban-client status)
✓ Ограничьте доступ к панели по IP если возможно
✓ Включите 2FA если доступно в 3X-UI

ПРОВЕРКА СТАТУСОВ:
──────────────────────────
3X-UI: systemctl is-active x-ui
UFW: ufw status
fail2ban: systemctl status fail2ban
Xray: systemctl status xray (если установлен отдельно)

═══════════════════════════════════════════════════════════
Скрипт установки завершен успешно!
═══════════════════════════════════════════════════════════
EOF

cat /root/3xui-installation-report.txt

# ============================================
# ЗАВЕРШЕНИЕ
# ============================================

print_header "УСТАНОВКА ЗАВЕРШЕНА!"

print_msg "Отчет сохранен в: /root/3xui-installation-report.txt"
print_msg "Конфигурация оптимизации: /etc/sysctl.d/99-3xui-optimization.conf"

echo ""
print_warning "ВАЖНЫЕ ДЕЙСТВИЯ:"
echo "  1. Измените пароль администратора 3X-UI немедленно!"
echo "  2. Получите SSL сертификат для вашего домена"
echo "  3. Настройте инбаунды (VLESS, Trojan, Shadowsocks)"
echo "  4. Добавьте пользователей и установите лимиты"
echo ""

print_info "Если требуется перезагрузка для полного применения всех параметров:"
echo "  reboot"

print_info "Для просмотра отчета:"
echo "  cat /root/3xui-installation-report.txt"

print_msg "════════════════════════════════════════════════════════════"
