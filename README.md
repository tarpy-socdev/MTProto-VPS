
***

## 1. Подготовка сервера

1. Подключаемся по SSH:

```bash
ssh root@IP_СЕРВЕРА
```

2. Обновляем систему и ставим зависимости:

```bash
apt update && apt upgrade -y
apt install git curl build-essential libssl-dev zlib1g-dev -y
```


***

## 2. Скачивание и сборка MTProxy

1. Клонируем репозиторий и переходим в него:

```bash
cd /opt
git clone https://github.com/GetPageSpeed/MTProxy
cd MTProxy
```


2. Собираем бинарник:

```bash
make
```

3. Копируем бинарник в рабочую папку и даём права:

```bash
cp objs/bin/mtproto-proxy /opt/MTProxy/
chmod +x /opt/MTProxy/mtproto-proxy
```


***

## 3. Секреты Telegram и конфиги

1. Скачиваем файлы от Telegram:

```bash
cd /opt/MTProxy
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
```


2. Генерируем свой секрет (ключ прокси):

```bash
head -c 16 /dev/urandom | xxd -ps
```

Пример секрета:  

```text
ae42f2f44619bfc8b0e5173867f0fc16
```

Сохрани его — он понадобится в юните и в ссылке для Telegram. [remadmin](https://remadmin.com/blog/linux/telegram-mtproto-proxy/)

***

## 4. Отдельный пользователь для сервиса

Создаём пользователя и отдаём ему каталог:

```bash
useradd -m -s /bin/false mtproxy
chown -R mtproxy:mtproxy /opt/MTProxy
```


***

## 5. systemd‑юнит для автозапуска

Создаём файл сервиса:

```bash
nano /etc/systemd/system/mtproto-proxy.service
```

Вставляем (подставь свой секрет и порт):

```ini
[Unit]
Description=Telegram MTProto Proxy Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
User=mtproxy
ExecStart=/opt/MTProxy/mtproto-proxy -u mtproxy -p 8888 -H 8080 -S ae42f2f44619bfc8b0e5173867f0fc16 --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Где:

- `-H 8080` — внешний порт прокси (можешь использовать 8080/8089/443/8443 и т.п.).  
- `-p 8888` — внутренний служебный порт.  
- `-S ...` — твой сгенерированный секрет. [github](https://github.com/TelegramMessenger/MTProxy/issues/344)

Сохраняем (Ctrl+O, Enter, Ctrl+X).

Активируем сервис:

```bash
systemctl daemon-reload
systemctl enable mtproto-proxy
systemctl restart mtproto-proxy
systemctl status mtproto-proxy
```

Должно быть `Active: active (running)` без ошибок `203/EXEC` или `217/USER`. [stackoverflow](https://stackoverflow.com/questions/45776003/fixing-a-systemd-service-203-exec-failure-no-such-file-or-directory)

***

## 6. Открываем порт в фаерволе

Если используется UFW:

```bash
ufw allow 8080/tcp
ufw reload
ufw status
```


При необходимости меняй `8080` на тот порт, который указал в `-H`.

***

## 7. Ссылка для Telegram

Формат:

```text
tg://proxy?server=IP_СЕРВЕРА&port=ПОРТ&secret=СЕКРЕТ
```
