#!/bin/bash

# =============================================
#   MTProto Proxy — Auto Install Script
#   github.com/tarpy-socdev/MTProto-VPS
# =============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Спиннер
spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${CYAN}${spin:$i:1}${NC}  $msg"
        sleep 0.1
    done
    printf "\r  ${GREEN}✓${NC}  $msg\n"
}

# --- Проверка root ---
[[ $EUID -ne 0 ]] && err "Запускай от root!"

clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     MTProto Proxy — Auto Installer       ║"
echo "  ║   github.com/tarpy-socdev/MTProto-VPS    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================
#   ШАГ 1 — Выбор порта
# =============================================
echo -e "${BOLD}Выбери порт для прокси:${NC}"
echo "  1) 443   (выглядит как HTTPS, лучший вариант)"
echo "  2) 8080  (популярный альтернативный)"
echo "  3) 8443  (ещё один безопасный)"
echo "  4) Ввести свой порт"
echo ""
read -rp "Твой выбор [1-4]: " PORT_CHOICE

case $PORT_CHOICE in
    1) PROXY_PORT=443 ;;
    2) PROXY_PORT=8080 ;;
    3) PROXY_PORT=8443 ;;
    4)
        read -rp "Введи порт (1-65535): " PROXY_PORT
        [[ ! "$PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ] && err "Некорректный порт!"
        ;;
    *) PROXY_PORT=8080 ;;
esac

echo ""

# =============================================
#   ШАГ 2 — От какого пользователя запускать
# =============================================
echo -e "${BOLD}От какого пользователя запускать сервис?${NC}"
echo "  1) root     (проще, работает с любым портом)"
echo "  2) mtproxy  (безопаснее, но нужен порт > 1024)"
echo ""
read -rp "Твой выбор [1-2]: " USER_CHOICE

NEED_CAP=0
case $USER_CHOICE in
    1) RUN_USER="root" ;;
    2)
        RUN_USER="mtproxy"
        if [ "$PROXY_PORT" -lt 1024 ]; then
            NEED_CAP=1
        fi
        ;;
    *) RUN_USER="root" ;;
esac

echo ""

INTERNAL_PORT=8888
INSTALL_DIR="/opt/MTProxy"
SERVICE_FILE="/etc/systemd/system/mtproto-proxy.service"

# =============================================
#   Установка (тихая, только спиннер)
# =============================================

# IP
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
[[ -z "$SERVER_IP" ]] && err "Не удалось определить IP сервера"

# Зависимости
( apt update -y && apt install -y git curl build-essential libssl-dev zlib1g-dev xxd ) > /dev/null 2>&1 &
spinner $! "Ставим зависимости..."

# Клонируем
( rm -rf "$INSTALL_DIR" && git clone https://github.com/GetPageSpeed/MTProxy "$INSTALL_DIR" ) > /dev/null 2>&1 &
spinner $! "Клонируем репозиторий MTProxy..."

# Собираем
( cd "$INSTALL_DIR" && make ) > /dev/null 2>&1 &
spinner $! "Собираем бинарник..."

# Копируем бинарник
cp "$INSTALL_DIR/objs/bin/mtproto-proxy" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mtproto-proxy"

# Конфиги Telegram
( curl -s https://core.telegram.org/getProxySecret -o "$INSTALL_DIR/proxy-secret" && \
  curl -s https://core.telegram.org/getProxyConfig -o "$INSTALL_DIR/proxy-multi.conf" ) > /dev/null 2>&1 &
spinner $! "Скачиваем конфиги Telegram..."

# Генерируем секрет
SECRET=$(head -c 16 /dev/urandom | xxd -ps)

# Юзер mtproxy (нужен всегда для флага -u)
if ! id "mtproxy" &>/dev/null; then
    useradd -m -s /bin/false mtproxy > /dev/null 2>&1
fi

if [ "$RUN_USER" = "mtproxy" ]; then
    chown -R mtproxy:mtproxy "$INSTALL_DIR"
else
    chown -R root:root "$INSTALL_DIR"
fi

if [ "$NEED_CAP" = "1" ]; then
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/mtproto-proxy"
fi

# Systemd сервис
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Telegram MTProto Proxy Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
User=$RUN_USER
ExecStart=$INSTALL_DIR/mtproto-proxy -u mtproxy -p $INTERNAL_PORT -H $PROXY_PORT -S $SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запускаем
( systemctl daemon-reload && systemctl enable mtproto-proxy && systemctl restart mtproto-proxy ) > /dev/null 2>&1 &
spinner $! "Запускаем сервис..."
sleep 2

# UFW
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    ( ufw delete allow "$PROXY_PORT/tcp" > /dev/null 2>&1 || true
      ufw allow "$PROXY_PORT/tcp" > /dev/null 2>&1
      echo "$UFW_STATUS" | grep -q "active" && ufw reload > /dev/null 2>&1 || true ) &
    spinner $! "Настраиваем UFW..."
fi

# =============================================
#   Тег спонсора
# =============================================
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Установка завершена!            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}${BOLD}  Что такое тег спонсора?${NC}"
echo ""
echo "  Когда пользователь подключается к твоему прокси,"
echo "  Telegram показывает ему плашку с названием канала"
echo "  или именем — это и есть тег спонсора."
echo "  Это бесплатный способ продвигать свой канал."
echo ""
echo -e "${YELLOW}${BOLD}  Как получить тег:${NC}"
echo ""
echo "  1. Открой @MTProxybot в Telegram"
echo "  2. Отправь команду /newproxy"
echo "  3. Бот попросит данные прокси — они ниже:"
echo ""
echo -e "  ┌─────────────────────────────────────────┐"
echo -e "  │  Host:Port  ${CYAN}${SERVER_IP}:${PROXY_PORT}${NC}"
echo -e "  │  Секрет     ${CYAN}${SECRET}${NC}"
echo -e "  └─────────────────────────────────────────┘"
echo ""
echo "  4. После создания бот выдаст тег — вставь его ниже"
echo ""
read -rp "  Введи тег (или Enter чтобы пропустить): " SPONSOR_TAG

if [ -n "$SPONSOR_TAG" ]; then
    sed -i "s|-M 1$|-M 1 -P $SPONSOR_TAG|" "$SERVICE_FILE"
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart mtproto-proxy > /dev/null 2>&1
    sleep 2
fi

# =============================================
#   Итог
# =============================================
if [ -n "$SPONSOR_TAG" ]; then
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}&t=${SPONSOR_TAG}"
else
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}"
fi

if systemctl is-active --quiet mtproto-proxy; then
    SVC_STATUS="${GREEN}✅ РАБОТАЕТ${NC}"
else
    SVC_STATUS="${RED}❌ ОШИБКА — запусти: journalctl -u mtproto-proxy -n 30${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════${NC}"
echo -e "  Статус:  $(echo -e $SVC_STATUS)"
echo -e "  Сервер:  ${CYAN}$SERVER_IP${NC}"
echo -e "  Порт:    ${CYAN}$PROXY_PORT${NC}"
echo -e "  Секрет:  ${CYAN}$SECRET${NC}"
[ -n "$SPONSOR_TAG" ] && echo -e "  Тег:     ${CYAN}$SPONSOR_TAG${NC}"
echo ""
echo -e "  ${YELLOW}${BOLD}📎 Ссылка для Telegram:${NC}"
echo -e "  ${GREEN}${BOLD}$PROXY_LINK${NC}"
echo ""
echo -e "  ${YELLOW}💡 Полезные команды:${NC}"
echo -e "  systemctl status mtproto-proxy"
echo -e "  journalctl -u mtproto-proxy -f"
echo -e "  systemctl restart mtproto-proxy"
echo ""#!/bin/bash

# =============================================
#   MTProto Proxy — Auto Install Script
#   github.com/tarpy-socdev/MTProto-VPS
# =============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Спиннер
spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${CYAN}${spin:$i:1}${NC}  $msg"
        sleep 0.1
    done
    printf "\r  ${GREEN}✓${NC}  $msg\n"
}

# --- Проверка root ---
[[ $EUID -ne 0 ]] && err "Запускай от root!"

clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     MTProto Proxy — Auto Installer       ║"
echo "  ║   github.com/tarpy-socdev/MTProto-VPS    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================
#   ШАГ 1 — Выбор порта
# =============================================
echo -e "${BOLD}Выбери порт для прокси:${NC}"
echo "  1) 443   (выглядит как HTTPS, лучший вариант)"
echo "  2) 8080  (популярный альтернативный)"
echo "  3) 8443  (ещё один безопасный)"
echo "  4) Ввести свой порт"
echo ""
read -rp "Твой выбор [1-4]: " PORT_CHOICE

case $PORT_CHOICE in
    1) PROXY_PORT=443 ;;
    2) PROXY_PORT=8080 ;;
    3) PROXY_PORT=8443 ;;
    4)
        read -rp "Введи порт (1-65535): " PROXY_PORT
        [[ ! "$PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ] && err "Некорректный порт!"
        ;;
    *) PROXY_PORT=8080 ;;
esac

echo ""

# =============================================
#   ШАГ 2 — От какого пользователя запускать
# =============================================
echo -e "${BOLD}От какого пользователя запускать сервис?${NC}"
echo "  1) root     (проще, работает с любым портом)"
echo "  2) mtproxy  (безопаснее, но нужен порт > 1024)"
echo ""
read -rp "Твой выбор [1-2]: " USER_CHOICE

NEED_CAP=0
case $USER_CHOICE in
    1) RUN_USER="root" ;;
    2)
        RUN_USER="mtproxy"
        if [ "$PROXY_PORT" -lt 1024 ]; then
            NEED_CAP=1
        fi
        ;;
    *) RUN_USER="root" ;;
esac

echo ""

INTERNAL_PORT=8888
INSTALL_DIR="/opt/MTProxy"
SERVICE_FILE="/etc/systemd/system/mtproto-proxy.service"

# =============================================
#   Установка (тихая, только спиннер)
# =============================================

# IP
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
[[ -z "$SERVER_IP" ]] && err "Не удалось определить IP сервера"

# Зависимости
( apt update -y && apt upgrade -y && apt install -y git curl build-essential libssl-dev zlib1g-dev xxd ) > /dev/null 2>&1 &
spinner $! "Обновляем систему и ставим зависимости..."

# Клонируем
( rm -rf "$INSTALL_DIR" && git clone https://github.com/GetPageSpeed/MTProxy "$INSTALL_DIR" ) > /dev/null 2>&1 &
spinner $! "Клонируем репозиторий MTProxy..."

# Собираем
( cd "$INSTALL_DIR" && make ) > /dev/null 2>&1 &
spinner $! "Собираем бинарник..."

# Копируем бинарник
cp "$INSTALL_DIR/objs/bin/mtproto-proxy" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mtproto-proxy"

# Конфиги Telegram
( curl -s https://core.telegram.org/getProxySecret -o "$INSTALL_DIR/proxy-secret" && \
  curl -s https://core.telegram.org/getProxyConfig -o "$INSTALL_DIR/proxy-multi.conf" ) > /dev/null 2>&1 &
spinner $! "Скачиваем конфиги Telegram..."

# Генерируем секрет
SECRET=$(head -c 16 /dev/urandom | xxd -ps)

# Юзер mtproxy (нужен всегда для флага -u)
if ! id "mtproxy" &>/dev/null; then
    useradd -m -s /bin/false mtproxy > /dev/null 2>&1
fi

if [ "$RUN_USER" = "mtproxy" ]; then
    chown -R mtproxy:mtproxy "$INSTALL_DIR"
else
    chown -R root:root "$INSTALL_DIR"
fi

if [ "$NEED_CAP" = "1" ]; then
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/mtproto-proxy"
fi

# Systemd сервис
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Telegram MTProto Proxy Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
User=$RUN_USER
ExecStart=$INSTALL_DIR/mtproto-proxy -u mtproxy -p $INTERNAL_PORT -H $PROXY_PORT -S $SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запускаем
( systemctl daemon-reload && systemctl enable mtproto-proxy && systemctl restart mtproto-proxy ) > /dev/null 2>&1 &
spinner $! "Запускаем сервис..."
sleep 2

# UFW
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    ( ufw delete allow "$PROXY_PORT/tcp" > /dev/null 2>&1 || true
      ufw allow "$PROXY_PORT/tcp" > /dev/null 2>&1
      echo "$UFW_STATUS" | grep -q "active" && ufw reload > /dev/null 2>&1 || true ) &
    spinner $! "Настраиваем UFW..."
fi

# =============================================
#   Тег спонсора
# =============================================
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Установка завершена!            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}${BOLD}  Что такое тег спонсора?${NC}"
echo ""
echo "  Когда пользователь подключается к твоему прокси,"
echo "  Telegram показывает ему плашку с названием канала"
echo "  или именем — это и есть тег спонсора."
echo "  Это бесплатный способ продвигать свой канал."
echo ""
echo -e "${YELLOW}${BOLD}  Как получить тег:${NC}"
echo ""
echo "  1. Открой @MTProxybot в Telegram"
echo "  2. Отправь команду /newproxy"
echo "  3. Бот попросит данные прокси — они ниже:"
echo ""
echo -e "  ┌─────────────────────────────────────────┐"
echo -e "  │  Host:Port  ${CYAN}${SERVER_IP}:${PROXY_PORT}${NC}"
echo -e "  │  Секрет     ${CYAN}${SECRET}${NC}"
echo -e "  └─────────────────────────────────────────┘"
echo ""
echo "  4. После создания бот выдаст тег — вставь его ниже"
echo ""
read -rp "  Введи тег (или Enter чтобы пропустить): " SPONSOR_TAG

if [ -n "$SPONSOR_TAG" ]; then
    sed -i "s|-M 1$|-M 1 -P $SPONSOR_TAG|" "$SERVICE_FILE"
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart mtproto-proxy > /dev/null 2>&1
    sleep 2
fi

# =============================================
#   Итог
# =============================================
if [ -n "$SPONSOR_TAG" ]; then
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}&t=${SPONSOR_TAG}"
else
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}"
fi

if systemctl is-active --quiet mtproto-proxy; then
    SVC_STATUS="${GREEN}✅ РАБОТАЕТ${NC}"
else
    SVC_STATUS="${RED}❌ ОШИБКА — запусти: journalctl -u mtproto-proxy -n 30${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════${NC}"
echo -e "  Статус:  $(echo -e $SVC_STATUS)"
echo -e "  Сервер:  ${CYAN}$SERVER_IP${NC}"
echo -e "  Порт:    ${CYAN}$PROXY_PORT${NC}"
echo -e "  Секрет:  ${CYAN}$SECRET${NC}"
[ -n "$SPONSOR_TAG" ] && echo -e "  Тег:     ${CYAN}$SPONSOR_TAG${NC}"
echo ""
echo -e "  ${YELLOW}${BOLD}📎 Ссылка для Telegram:${NC}"
echo -e "  ${GREEN}${BOLD}$PROXY_LINK${NC}"
echo ""
echo -e "  ${YELLOW}💡 Полезные команды:${NC}"
echo -e "  systemctl status mtproto-proxy"
echo -e "  journalctl -u mtproto-proxy -f"
echo -e "  systemctl restart mtproto-proxy"
echo ""
