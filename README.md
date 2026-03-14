# 📡 MTProto Proxy — Ручная установка на VPS

![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange)

Пошаговая инструкция по ручной установке MTProto прокси для Telegram на Linux VPS.

> 💡 Хочешь автоматическую установку с менеджером?  
> → [tarpy-socdev/MTP-manager](https://github.com/tarpy-socdev/MTP-manager)

---

## 📋 Содержание

1. [Подготовка сервера](#1-подготовка-сервера)
2. [Сборка MTProxy](#2-сборка-mtproxy)
3. [Секреты и конфиги Telegram](#3-секреты-и-конфиги-telegram)
4. [Отдельный пользователь](#4-отдельный-пользователь)
5. [Systemd-сервис](#5-systemd-сервис)
6. [Открыть порт в фаерволе](#6-открыть-порт-в-фаерволе)
7. [Ссылка для подключения](#7-ссылка-для-подключения)

---

## 1. Подготовка сервера

Подключаемся по SSH и обновляем систему:

```bash
ssh root@IP_СЕРВЕРА
```

```bash
apt update && apt upgrade -y
apt install -y git curl build-essential libssl-dev zlib1g-dev xxd
```

---

## 2. Сборка MTProxy

Клонируем репозиторий и собираем бинарник:

```bash
cd /opt
git clone https://github.com/GetPageSpeed/MTProxy
cd MTProxy
make -j$(nproc)
```

Копируем бинарник и выставляем права:

```bash
cp objs/bin/mtproto-proxy /opt/MTProxy/
chmod +x /opt/MTProxy/mtproto-proxy
```

---

## 3. Секреты и конфиги Telegram

Скачиваем файлы конфигурации от Telegram:

```bash
cd /opt/MTProxy
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
```

Генерируем секрет прокси:

```bash
head -c 16 /dev/urandom | xxd -ps
```

Пример вывода:
```
ae42f2f44619bfc8b0e5173867f0fc16
```

> ⚠️ Сохрани секрет — он нужен в конфиге сервиса и в ссылке для клиентов.

---

## 4. Отдельный пользователь

Создаём непривилегированного пользователя для сервиса:

```bash
useradd -r -s /bin/false mtproxy
chown -R mtproxy:mtproxy /opt/MTProxy
```

---

## 5. Systemd-сервис

Создаём файл сервиса:

```bash
nano /etc/systemd/system/mtproto-proxy.service
```

Вставляем содержимое (замени `СЕКРЕТ` и при необходимости порт):

```ini
[Unit]
Description=Telegram MTProto Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
User=mtproxy
ExecStart=/opt/MTProxy/mtproto-proxy \
  -u mtproxy \
  -p 8888 \
  -H 8080 \
  -S СЕКРЕТ \
  --aes-pwd proxy-secret proxy-multi.conf \
  -M 1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

| Параметр | Описание |
|---------|----------|
| `-H 8080` | Внешний порт прокси (443 / 8080 / 8443 и т.п.) |
| `-p 8888` | Внутренний служебный порт |
| `-S ...` | Твой сгенерированный секрет |

Активируем и запускаем:

```bash
systemctl daemon-reload
systemctl enable mtproto-proxy
systemctl restart mtproto-proxy
systemctl status mtproto-proxy
```

В выводе должно быть `Active: active (running)`.

---

## 6. Открыть порт в фаерволе

Если используется UFW:

```bash
ufw allow 8080/tcp
ufw reload
```

> Замени `8080` на порт из параметра `-H` в конфиге сервиса.

---

## 7. Ссылка для подключения

```
tg://proxy?server=IP_СЕРВЕРА&port=ПОРТ&secret=СЕКРЕТ
```

Пример:
```
tg://proxy?server=1.2.3.4&port=8080&secret=ae42f2f44619bfc8b0e5173867f0fc16
```

Отправь ссылку себе в Telegram — при нажатии предложит подключиться к прокси.

---

## 🔄 Обновление конфигов Telegram

Telegram периодически меняет файлы `proxy-secret` и `proxy-multi.conf`. Если прокси перестал работать — обнови их:

```bash
curl -s https://core.telegram.org/getProxySecret -o /opt/MTProxy/proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf
systemctl restart mtproto-proxy
```

---

## 📄 Лицензия

MIT License © 2026
