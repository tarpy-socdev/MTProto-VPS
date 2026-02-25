#!/bin/bash

# =============================================
#   MTProto Proxy — Uninstall Script
#   github.com/tarpy-socdev/MTProto-VPS
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Проверка root ---
[[ $EUID -ne 0 ]] && err "Запускай от root!"

clear
echo -e "${RED}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     MTProto Proxy — Uninstaller          ║"
echo "  ║   github.com/tarpy-socdev/MTProto-VPS    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- Показываем что будет удалено ---
echo -e "${BOLD}Будет удалено:${NC}"
echo "  • Сервис mtproto-proxy (systemd)"
echo "  • Папка /opt/MTProxy"
echo "  • Пользователь mtproxy"
echo "  • Правило UFW для порта прокси"
echo ""

read -rp "Продолжить? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Отменено.${NC}"
    exit 0
fi

echo ""

# --- Получаем порт из сервиса перед удалением (для UFW) ---
PROXY_PORT=""
if [ -f /etc/systemd/system/mtproto-proxy.service ]; then
    PROXY_PORT=$(grep -oP '(?<=-H )\d+' /etc/systemd/system/mtproto-proxy.service || true)
fi

# --- Останавливаем и удаляем сервис ---
if systemctl is-active --quiet mtproto-proxy 2>/dev/null; then
    log "Останавливаем сервис..."
    systemctl stop mtproto-proxy
fi

if systemctl is-enabled --quiet mtproto-proxy 2>/dev/null; then
    log "Отключаем автозапуск..."
    systemctl disable mtproto-proxy
fi

if [ -f /etc/systemd/system/mtproto-proxy.service ]; then
    log "Удаляем systemd юнит..."
    rm -f /etc/systemd/system/mtproto-proxy.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
fi

# --- Удаляем папку ---
if [ -d /opt/MTProxy ]; then
    log "Удаляем /opt/MTProxy..."
    rm -rf /opt/MTProxy
fi

# --- Удаляем пользователя ---
if id "mtproxy" &>/dev/null; then
    log "Удаляем пользователя mtproxy..."
    userdel -r mtproxy 2>/dev/null || userdel mtproxy 2>/dev/null || true
fi

# --- Убираем правило UFW ---
if [ -n "$PROXY_PORT" ] && command -v ufw &>/dev/null; then
    log "Удаляем правило UFW для порта $PROXY_PORT..."
    ufw delete allow "$PROXY_PORT/tcp" > /dev/null 2>&1 || true
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        ufw reload > /dev/null 2>&1 || true
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       MTProto Proxy удалён!              ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${CYAN}Что было удалено:${NC}"
echo "  ✓ Сервис mtproto-proxy"
echo "  ✓ Папка /opt/MTProxy"
echo "  ✓ Пользователь mtproxy"
[ -n "$PROXY_PORT" ] && echo "  ✓ Правило UFW (порт $PROXY_PORT)" || echo "  — Правило UFW (порт не определён, проверь вручную)"
echo ""
