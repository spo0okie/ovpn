# ovpn
Конфиг и скрипты для управления опенвпном

Один набор скриптов на оба сценария. Единица доступа — **инстанс**
OpenVPN (имя, адрес, порт, подсеть, маршруты, режим аутентификации,
каталог публикации CCD). Одиночный сервер — частный случай: `instances`
не задан, работает дефолтный инстанс `local` на legacy-переменных
(`srvaddr/port/proto/vpnnet/subnets/dns/use2fa`), CCD без суффикса.
Несколько инстансов (в т.ч. на разных площадках) — `instances="..."`
в `_config`. Канон модели — [plans/migration-instance-model.md](../plans/migration-instance-model.md).
Как раскладывать файлы и инициализировать один/несколько инстансов — см.
[Инстансы: раскладка файлов и инициализация](#инстансы-раскладка-файлов-и-инициализация).

### Возможности

Жизненный цикл сервера:
- инициализация с нуля (`_reset.sh`): CA, серверный ключ/серт,
  dh, ta.key, пустой CRL; в одиночном режиме — `server.conf`,
  при `instances` — `server-<instance>.conf` на каждый (для 2FA-инстанса
  — PAM `openvpn-plugin-auth-pam.so` + `setenv OPENVPN_SERVER_NAME <instance>`);
- продление CA (`_renew.CA.sh`, `usr.new ca`) и серверного сертификата
  (`usr.new serv`);
- перевыпуск CRL на 720 дней (`upd.crl`);
- заглушка `route-client` (client-connect hook), `update-resolv-conf`
  для linux-клиентов.

Жизненный цикл пользователя:
- создание/обновление (`usr.new`): ключ, CSR, сертификат (один раз),
  CCD и готовый конфиг на **каждый инстанс** (`<prefix>_<CN>_<instance>.ovpn`,
  в одиночном режиме — `<prefix>_<CN>.ovpn`), обертки
  `_renew`/`_enable`/`_disable`/`_send` в папке клиента;
- CCD на инстанс — `usr.gen.ccd <user> [instance] [noupdate]` (файл
  `ccd.<instance>`, дефолтный — `ccd`);
- публикация состояния на инстанс — единый `usr.publish <user> [instance]`
  (`<instance>_delivery=local` — симлинк в `<instance>_ccd_dir`; `ssh` —
  как прежний `usr.push`). `usr.enable`/`usr.disable` — тонкие обертки
  над ним;
- отзыв (`usr.revoke`): CRL, архив конфига с таймстампом;
- просмотр сертификатов (`usr.show`: пользователь/ca/server/revoked).

Сети и адреса:
- CCD: фиксированный адрес (`ifconfig-push`) + пуш маршрутов инстанса;
- массовая смена подсетей: `previousVpnnet`/`previousSubnets` (или
  `<instance>_previous_lan/_routes`) — при обходе пользователей
  стандартные CCD обновляются автоматически, кастомные не трогаются
  (рядом кладутся `ccd.new`/`ccd.old`);
- интеграция с инвентори (`inventoryApiUrl`): выдача закрепленного или
  первого свободного IP, регистрация адреса за конфигом и пользователем;
  имя IP-записи = `<instance>_inv_prefix` + CN (дефолт `ovpn-`, для
  2FA — `ovpn2fa-`).

Опции:
- 2FA: атрибут инстанса `auth_mode=2fa` (в одиночном режиме — `use2fa=1`):
  генерация секрета Google Authenticator в папке клиента, публикация в
  `<instance>_gauth_dir` при `usr.publish`;
- пароль на приватный ключ: `usePassKey=1` (пароль в `passwd.txt`);
- конфиг для OpenVPN Connect: `makeConnectConf=1` (`*_connect.ovpn`);
- доставка конфигов (`usr.send`): шара в Nextcloud (`nextcloudUrl`) или
  письмо с вложениями через авторизованный SMTP (`mailSmtpUrl` — когда
  Nextcloud недоступен снаружи); пароль ключа и код 2FA — вторым
  каналом по СМС (`smsApiUrl`). При почтовой доставке рекомендуется
  `usePassKey=1`: перехват письма без СМС с паролем бесполезен.

Исторический мультисайтовый сценарий — [multisite/](multisite/README.md)
(архив; перенос данных в инстанс-модель — `multisite/migrate-to-instances.sh`).

Тесты: [tests/README.md](tests/README.md).

## Инстансы: раскладка файлов и инициализация

Всё живёт в одном каталоге `$ovpndir` (в примерах — `/etc/openvpn`), из
которого и выполняются скрипты. Общая инфраструктура доверия (CA, серверный
сертификат, `ta.key`, `dh1024.pem`, CRL) — **одна на все инстансы**. На каждый
инстанс — свой `server-<instance>.conf`, свой каталог публикации CCD и свои
клиентские конфиги.

Раскладка для `instances="local local-2fa"`:

```
/etc/openvpn/
├── _config                       # описание всех инстансов
├── ca.pem / ca.key               # общий CA
├── <prefix>-serv.cert/.key       # общий серверный сертификат
├── ta.key / dh1024.pem           # общие
├── server-local.conf             # конфиг инстанса "local"
├── server-local-2fa.conf         # конфиг инстанса "local-2fa"
├── ccd/                          # <local_ccd_dir>    — опубликованные CCD "local"
├── ccd-2fa/                      # <local_2fa_ccd_dir> — опубликованные CCD "local-2fa"
├── clients/
│   ├── <prefix>-ivanov-ii/              # папка клиентской учётной записи (CN)
│   │   ├── <prefix>_ivanov-ii.key       # закрытый ключ (общий на все инстансы)
│   │   ├── <prefix>_ivanov-ii.crt       # сертификат (общий)
│   │   ├── ccd.local             # CCD-исходник для "local"
│   │   ├── ccd.local-2fa         # CCD-исходник для "local-2fa"
│   │   ├── <prefix>_ivanov-ii_local.ovpn      # клиентский конфиг для "local"
│   │   ├── <prefix>_ivanov-ii_local-2fa.ovpn  # клиентский конфиг для "local-2fa"
│   │   ├── google.txt            # секрет 2FA (если есть 2FA-инстанс)
│   │   └── _renew / _enable / _disable / _send
│   └── revoked/                  # архив отозванных папок
│   └── revoked.crl               # список отозванных сертификатов (CRL)
└── certs/                        # историческая раскладка сертификатов (опционально)
```

Отличия вырожденного (single) случая — `instances` не задан:
`server.conf` вместо `server-*.conf`, один каталог `ccd/`, CCD без суффикса
(`ccd`), конфиг без суффикса инстанса (`<prefix>_<CN>.ovpn`).

### Инициализация одного инстанса

```bash
git clone https://github.com/spo0okie/ovpn.git .   # в $ovpndir
mv _config.sample _config
```
заполняем `_config` базовыми переменными (`org`, `prefix`, `srvname`,
`srvaddr`, `proto`, `port`, `vpnnet`, `subnets`, `dns`) — **без** `instances`, затем:
```bash
./_reset.sh             # CA, серверный ключ/серт, ta, dh, server.conf, ccd/, clients/
./usr.new username      # ключ/серт + ccd + <prefix>_username.ovpn
./usr.enable username   # симлинк ccd/username (публикация CCD)
```

### Инициализация нескольких инстансов

Проще всего задать топологию **до первого `_reset.sh`** — тогда CA/серверный
сертификат генерируются один раз, а под каждый инстанс создаётся свой конфиг:

```sh
# _config
instances="local local-2fa"
local_addr="ovpn.example.org"   local_port=1194  local_lan=192.168.77.0/24
local_routes="192.168.77.0/24 172.20.0.0/16"     local_dns="192.168.77.2"
local_auth_mode=normal          local_ccd_dir=/etc/openvpn/ccd    local_delivery=local
local_2fa_addr="ovpn.example.org" local_2fa_port=1196 local_2fa_lan=192.168.178.0/24
local_2fa_routes="192.168.178.0/24"              local_2fa_auth_mode=2fa
local_2fa_ccd_dir=/etc/openvpn/ccd-2fa           local_2fa_delivery=local
local_2fa_gauth_dir=/etc/google-auth
```
```bash
./_reset.sh              # server-local.conf + server-local-2fa.conf (общие CA/серт/dh/ta)
./usr.new username       # ccd.local, ccd.local-2fa + конфиги на каждый инстанс
./usr.publish username   # CCD в ccd/username и ccd-2fa/username (+ google.txt в gauth_dir)
```

### Добавить второй инстанс к существующему

`_reset.sh` **разрушителен**: он пересоздаёт CA, после чего все ранее выданные
сертификаты становятся недействительными. Поэтому есть два пути.

**A. Некритичная среда (dev/test, или готовы перевыпустить сертификаты).**
Добавить `instances` + переменные инстансов в `_config` и снова выполнить
`./_reset.sh`, затем пересоздать пользователей. Никаких ручных действий.

**B. Боевой сервер — без перевыпуска CA.** Инстанс добавляется вручную, CA не
трогается:
1. в `_config` прописать `instances` и переменные нового инстанса;
2. переименовать `server.conf` → `server-local.conf` (по соглашению имён) и
   сделать копию под второй инстанс `server-local-2fa.conf`, поменяв в ней:
   `port`, `server <lan> <mask>`, `status`/`log-append`/`ifconfig-pool-persist`
   (суффикс `-local-2fa`), `client-config-dir <ccd_dir>`; для 2FA добавить
   `plugin .../openvpn-plugin-auth-pam.so openvpn` и
   `setenv OPENVPN_SERVER_NAME local-2fa`;
3. создать каталог публикации CCD (`local_2fa_ccd_dir`) и, для 2FA, `gauth_dir`;
4. CA/`<prefix>-serv.cert`/`ta.key`/`dh1024.pem` — общие, их не трогать;
5. пересоздать клиентские данные под новую схему: старый CCD (`ccd`) и конфиг
   (`<prefix>_<CN>.ovpn`) переименовать в `ccd.local` / `<prefix>_<CN>_local.ovpn`
   либо просто запустить `./usr.new username` для каждого пользователя
   (он досоздаст `ccd.local` и конфиг; старые файлы удалить вручную), затем
   `./usr.publish username`.

### Несколько хостов (доставка по ssh)

Если инстанс живёт на отдельном сервере, в его описании меняется только способ
доставки — раскладка на узле управления та же:

```sh
local_delivery=ssh
local_ssh_host=ovpn.contoso.local
local_ssh_key=/root/.ssh/openvpn.control
local_ccd_dir=/etc/openvpn/ccd          # каталог CCD НА удалённом сервере
local_gauth_dir=/etc/google-auth        # (для 2FA) каталог секретов на сервере
```

`usr.publish`/`usr.enable`/`usr.disable` будут раскладывать CCD и 2FA-секреты
по ssh (вместо симлинка в локальный каталог); CA и папки клиентов остаются на
узле управления.

### Установка:
в папке /etc/openvpn делаем
```bash
git clone https://github.com/spo0okie/ovpn.git .  #скачиваем скрипты
mv _config.sample _config                         #сэмпл кофиг переименовываем в боевой
chmod 755 _reset.sh                               #разрешаем инициировать инстанс openvpn
```
  
заполняем _config  
заполняем openssl.cfg (по желанию)
выполняем  
  
```bash
_reset.sh                                         #инициируем инстанс openvpn
chmod 644 _reset.sh                               #защищаемся от переинициализации боевого инстанса
```

### создать пользователя
```bash
usr.new username
```
конфиг пользователя кладется в `clients/prefix-username/prefix_username.ovpn`
(при нескольких инстансах — по конфигу на инстанс: `prefix_username_<instance>.ovpn`)
таким же образом можно обновить пользователя

### Рабочий цикл (multi-instance)
```sh
./usr.new ivanov-ii                  # ключ/серт + CCD и конфиги по всем инстансам
./usr.gen.ccd ivanov-ii local-2fa    # выдать/обновить CCD конкретного инстанса
./usr.publish ivanov-ii              # раскатать CCD (и 2FA-секреты) на инстансы
./usr.send ivanov-ii                 # доставить конфиги + пароли
```
Отключение/включение: `./usr.disable ivanov-ii [instance]`,
`./usr.enable ivanov-ii [instance]` (без инстанса — по всем доступным).

### Обход всех пользователей
Пример пересборки CCD файла (в одиночном режиме — `ccd`, при инстансах — `ccd.<instance>`)
```bash
for f in ./clients/prefix-*; do rm -f $f/ccd*; $f/_renew; done
```

### Тесты
```bash
bash tests/run.sh
```
Проверяют генерацию CCD (включая миграцию подсетей и noupdate), работу
с инвентори, 2FA и инстанс-модель (конфиги на инстанс, `usr.publish`
local/ssh). Внешние сервисы подменяются заглушками, боевые данные не
трогаются — можно запускать где угодно, нужны только bash и jq.
Автоматически гоняются в GitHub Actions.

### Обновление скриптов на работающем сервере

Скрипты можно раскатывать поверх живого сервера (`git pull`): все
окружение-специфичное (`_config`, `clients/`, `ccd/`, ключи, `server.conf`)
в `.gitignore` и не затрагивается. После обновления проверить:

1. `_config`: если инвентори требует авторизацию — логин/пароль теперь
   указываются прямо в `inventoryApiUrl`
   (`https://user:password@inventory.../web/api`), отдельного хардкода
   в скриптах больше нет;
2. новые опции в `_config.sample`: `instances` + per-instance переменные
   (`<instance>_lan/_routes/_port/_addr/_auth_mode/_ccd_dir/_delivery/...`),
   `previousVpnnet`/`previousSubnets` (для массовой смены подсетей) —
   перенести в `_config` по необходимости;
3. права на исполнение: `chmod 755 usr.* upd.crl` (git их хранит, но
   проверить не мешает).
