#!/bin/bash
# ==============================================
# MTProto Proxy — Auto Install Script v2.0
# github.com/tarpy-socdev/MTProto-VPS
# ==============================================
set -e

# ============ ЦВЕТА И СТИЛИ ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============ ФУНКЦИИ ============

err() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

info() {
    echo -e "${CYAN}[ℹ]${NC} $1"
}

# Спиннер с улучшением
spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r ${CYAN}${spin:$i:1}${NC} $msg"
        sleep 0.1
    done
    # Проверяем код выхода процесса
    wait "$pid" 2>/dev/null
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r ${GREEN}✓${NC} $msg\n"
    else
        printf "\r ${RED}✗${NC} $msg (ошибка $exit_code)\n"
        return $exit_code
    fi
}

# Валидация порта
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        err "❌ Некорректный порт! Используй 1-65535"
    fi
}

# Проверка доступности порта
check_port_available() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        err "❌ Порт $port уже занят! Выбери другой"
    fi
}

# Генерация QR-кода
generate_qr_code() {
    local data=$1
    local output_file=$2
    
    # Проверяем наличие утилит
    if ! command -v qrencode &>/dev/null; then
        info "Устанавливаем qrencode для QR-кодов..."
        apt install -y qrencode > /dev/null 2>&1
    fi
    
    # Генерируем QR-код в текстовом виде (ANSI) и в файл PNG
    qrencode -t ANSI -o - "$data" 2>/dev/null || echo "[QR-код недоступен]"
    qrencode -o "$output_file" "$data" 2>/dev/null || true
}

# Проверка root
[[ $EUID -ne 0 ]] && err "⚠️ Запускай от root! (sudo bash script.sh)"

clear
echo -e "${CYAN}${BOLD}"
echo " ╔══════════════════════════════════════════╗"
echo " ║   MTProto Proxy — Auto Installer v2.0   ║"
echo " ║   github.com/tarpy-socdev/MTProto-VPS   ║"
echo " ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ============ ШАГ 1 — Выбор порта ============
echo -e "${BOLD}🔧 Выбери порт для прокси:${NC}"
echo " 1) 443 (выглядит как HTTPS, лучший вариант)"
echo " 2) 8080 (популярный альтернативный)"
echo " 3) 8443 (ещё один безопасный)"
echo " 4) Ввести свой порт"
echo ""
read -rp "Твой выбор [1-4]: " PORT_CHOICE

case $PORT_CHOICE in
    1) PROXY_PORT=443 ;;
    2) PROXY_PORT=8080 ;;
    3) PROXY_PORT=8443 ;;
    4) 
        read -rp "Введи порт (1-65535): " PROXY_PORT
        validate_port "$PROXY_PORT"
        ;;
    *) 
        info "Значение по умолчанию: 8080"
        PROXY_PORT=8080
        ;;
esac

# Проверяем доступность порта
check_port_available "$PROXY_PORT"
info "Используем порт: $PROXY_PORT"
echo ""

# ============ ШАГ 2 — От какого пользователя запускать ============
echo -e "${BOLD}👤 От какого пользователя запускать сервис?${NC}"
echo " 1) root (проще, работает с любым портом)"
echo " 2) mtproxy (безопаснее, но нужен порт > 1024)"
echo ""
read -rp "Твой выбор [1-2]: " USER_CHOICE

NEED_CAP=0
case $USER_CHOICE in
    1) RUN_USER="root" ;;
    2) 
        RUN_USER="mtproxy"
        if [ "$PROXY_PORT" -lt 1024 ]; then
            info "Для портов < 1024 будет использована возможность CAP_NET_BIND_SERVICE"
            NEED_CAP=1
        fi
        ;;
    *) 
        info "Значение по умолчанию: root"
        RUN_USER="root"
        ;;
esac

echo -e "${CYAN}✓ Пользователь: $RUN_USER${NC}"
echo ""

# ============ ПЕРЕМЕННЫЕ ============
INTERNAL_PORT=8888
INSTALL_DIR="/opt/MTProxy"
SERVICE_FILE="/etc/systemd/system/mtproto-proxy.service"
QR_OUTPUT="$INSTALL_DIR/proxy-qrcode.png"
LOGFILE="/tmp/mtproto-install.log"

# ============ ПОЛУЧЕНИЕ IP СЕРВЕРА ============
info "Определяем IP адрес сервера..."
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 3 https://ifconfig.me 2>/dev/null || \
            hostname -I | awk '{print $1}')

if [[ -z "$SERVER_IP" ]]; then
    err "❌ Не удалось определить IP сервера. Проверь подключение к интернету"
fi

echo -e "${CYAN}✓ IP сервера: $SERVER_IP${NC}"
echo ""

# ============ УСТАНОВКА (ТИХАЯ) ============
info "Начинаем установку..."
echo ""

# Системные зависимости
(
    apt update -y > "$LOGFILE" 2>&1
    apt upgrade -y >> "$LOGFILE" 2>&1
    apt install -y git curl build-essential libssl-dev zlib1g-dev xxd netcat-openbsd >> "$LOGFILE" 2>&1
) &
spinner $! "Обновляем систему и ставим зависимости..."

# Клонируем репозиторий
(
    rm -rf "$INSTALL_DIR"
    git clone https://github.com/GetPageSpeed/MTProxy "$INSTALL_DIR" >> "$LOGFILE" 2>&1
) &
spinner $! "Клонируем репозиторий MTProxy..."

# Проверяем наличие исходников
if [ ! -f "$INSTALL_DIR/Makefile" ]; then
    err "❌ Ошибка загрузки репозитория! Проверь интернет"
fi

# Собираем бинарник
(
    cd "$INSTALL_DIR" && make >> "$LOGFILE" 2>&1
) &
spinner $! "Собираем бинарник..."

# Проверяем наличие собранного бинарника
if [ ! -f "$INSTALL_DIR/objs/bin/mtproto-proxy" ]; then
    err "❌ Ошибка компиляции! Смотри лог: $LOGFILE"
fi

# Копируем бинарник
cp "$INSTALL_DIR/objs/bin/mtproto-proxy" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mtproto-proxy"
success "Бинарник скопирован"

# Скачиваем конфиги Telegram
(
    curl -s --max-time 10 https://core.telegram.org/getProxySecret -o "$INSTALL_DIR/proxy-secret" >> "$LOGFILE" 2>&1
    curl -s --max-time 10 https://core.telegram.org/getProxyConfig -o "$INSTALL_DIR/proxy-multi.conf" >> "$LOGFILE" 2>&1
) &
spinner $! "Скачиваем конфиги Telegram..."

# Проверяем файлы конфигов
if [ ! -s "$INSTALL_DIR/proxy-secret" ] || [ ! -s "$INSTALL_DIR/proxy-multi.conf" ]; then
    err "❌ Ошибка загрузки конфигов Telegram! Проверь подключение"
fi

# Генерируем секрет (16 байт = 32 символа в hex)
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo "$SECRET" > "$INSTALL_DIR/secret.txt"  # Сохраняем для резервной копии
success "Секрет сгенерирован"

# Создаём пользователя mtproxy (если его нет)
if ! id "mtproxy" &>/dev/null; then
    useradd -m -s /bin/false mtproxy > /dev/null 2>&1
    success "Пользователь mtproxy создан"
fi

# Настраиваем права доступа
if [ "$RUN_USER" = "mtproxy" ]; then
    chown -R mtproxy:mtproxy "$INSTALL_DIR"
else
    chown -R root:root "$INSTALL_DIR"
fi

# Если нужны capabilities
if [ "$NEED_CAP" = "1" ]; then
    setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/mtproto-proxy"
    success "Установлены capabilities для привилегированного порта"
fi

# ============ СОЗДАНИЕ SYSTEMD СЕРВИСА ============
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Telegram MTProto Proxy Server
After=network.target
Documentation=https://github.com/GetPageSpeed/MTProxy

[Service]
Type=simple
WorkingDirectory=INSTALL_DIR
User=RUN_USER
ExecStart=INSTALL_DIR/mtproto-proxy -u mtproxy -p INTERNAL_PORT -H PROXY_PORT -S SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1 SPONSOR_TAG_FLAG
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Подставляем переменные (сначала готовим спонсорский тег как пусто)
SPONSOR_TAG_FLAG=""
sed -i "s|INSTALL_DIR|$INSTALL_DIR|g" "$SERVICE_FILE"
sed -i "s|RUN_USER|$RUN_USER|g" "$SERVICE_FILE"
sed -i "s|INTERNAL_PORT|$INTERNAL_PORT|g" "$SERVICE_FILE"
sed -i "s|PROXY_PORT|$PROXY_PORT|g" "$SERVICE_FILE"
sed -i "s|SECRET|$SECRET|g" "$SERVICE_FILE"
sed -i "s|SPONSOR_TAG_FLAG|$SPONSOR_TAG_FLAG|g" "$SERVICE_FILE"

success "Systemd сервис создан"

# Запускаем сервис
(
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable mtproto-proxy > /dev/null 2>&1
    systemctl restart mtproto-proxy > /dev/null 2>&1
) &
spinner $! "Запускаем сервис..."

sleep 3

# Проверяем статус сервиса
if ! systemctl is-active --quiet mtproto-proxy; then
    echo ""
    err "❌ Сервис не запустился! Смотри лог:"
fi

success "Сервис запущен"

# ============ НАСТРОЙКА ФАЙРВОЛА (UFW) ============
if command -v ufw &>/dev/null; then
    (
        ufw delete allow "$PROXY_PORT/tcp" > /dev/null 2>&1 || true
        ufw allow "$PROXY_PORT/tcp" > /dev/null 2>&1
        UFW_STATUS=$(ufw status | head -1)
        if echo "$UFW_STATUS" | grep -q "active"; then
            ufw reload > /dev/null 2>&1
        fi
    ) &
    spinner $! "Настраиваем UFW..."
fi

# ============ СПОНСОРСКИЙ ТАГ ============
clear
echo -e "${CYAN}${BOLD}"
echo " ╔══════════════════════════════════════════╗"
echo " ║         Установка завершена!            ║"
echo " ╚══════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}${BOLD}📌 Что такое тег спонсора?${NC}"
echo ""
echo " Когда пользователь подключается к твоему прокси,"
echo " Telegram показывает ему плашку с названием канала"
echo " или именем — это и есть тег спонсора."
echo " Это бесплатный способ продвигать свой канал."
echo ""

echo -e "${YELLOW}${BOLD}🔗 Как получить тег:${NC}"
echo ""
echo " 1. Открой @MTProxybot в Telegram"
echo " 2. Отправь команду /newproxy"
echo " 3. Бот попросит данные прокси — они ниже:"
echo ""
echo -e " ┌─────────────────────────────────────────┐"
echo -e " │ Host:Port ${CYAN}${SERVER_IP}:${PROXY_PORT}${NC}"
echo -e " │ Секрет    ${CYAN}${SECRET}${NC}"
echo -e " └─────────────────────────────────────────┘"
echo ""
echo " 4. После создания бот выдаст тег — вставь его ниже"
echo ""
read -rp " Введи тег (или Enter чтобы пропустить): " SPONSOR_TAG

if [ -n "$SPONSOR_TAG" ]; then
    sed -i "s|-M 1$|-M 1 -P $SPONSOR_TAG|" "$SERVICE_FILE"
    systemctl daemon-reload > /dev/null 2>&1
    systemctl restart mtproto-proxy > /dev/null 2>&1
    sleep 2
    success "Тег добавлен и сервис перезагружен"
fi

# ============ ИТОГОВАЯ ИНФОРМАЦИЯ ============
# Формируем ссылку
if [ -n "$SPONSOR_TAG" ]; then
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}&t=${SPONSOR_TAG}"
else
    PROXY_LINK="tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}"
fi

# Проверяем финальный статус
if systemctl is-active --quiet mtproto-proxy; then
    SVC_STATUS="${GREEN}✅ РАБОТАЕТ${NC}"
else
    SVC_STATUS="${RED}❌ ОШИБКА${NC}"
fi

clear
echo -e "${GREEN}${BOLD}"
echo " ════════════════════════════════════════════"
echo " 🎉 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! 🎉"
echo -e "${NC}"
echo ""
echo -e " ${YELLOW}Статус:${NC} $(echo -e $SVC_STATUS)"
echo -e " ${YELLOW}Сервер:${NC} ${CYAN}$SERVER_IP${NC}"
echo -e " ${YELLOW}Порт:${NC} ${CYAN}$PROXY_PORT${NC}"
echo -e " ${YELLOW}Секрет:${NC} ${CYAN}$SECRET${NC}"
[ -n "$SPONSOR_TAG" ] && echo -e " ${YELLOW}Тег:${NC} ${CYAN}$SPONSOR_TAG${NC}"
echo ""

# ============ QR-КОД ============
echo -e "${YELLOW}${BOLD}📱 QR-код для подключения:${NC}"
echo ""

# Генерируем и показываем QR-код
generate_qr_code "$PROXY_LINK" "$QR_OUTPUT"

if [ -f "$QR_OUTPUT" ]; then
    echo -e "${GREEN}✓ QR-код сохранён: $QR_OUTPUT${NC}"
fi

echo ""
echo -e "${YELLOW}${BOLD}🔗 Ссылка для Telegram:${NC}"
echo -e "${GREEN}${BOLD}$PROXY_LINK${NC}"
echo ""

# ============ ПОЛЕЗНЫЕ КОМАНДЫ ============
echo -e "${YELLOW}${BOLD}💡 Полезные команды:${NC}"
echo " systemctl status mtproto-proxy"
echo " systemctl restart mtproto-proxy"
echo " journalctl -u mtproto-proxy -f"
echo " journalctl -u mtproto-proxy -n 50"
echo ""

echo -e "${CYAN}${BOLD}📂 Файлы:${NC}"
echo " Конфиг сервиса: $SERVICE_FILE"
echo " Директория: $INSTALL_DIR"
echo " Логи установки: $LOGFILE"
echo " QR-код: $QR_OUTPUT"
echo ""

echo -e "${YELLOW}ℹ️ Сохрани эту информацию в безопасном месте!${NC}"
echo ""
