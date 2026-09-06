# План унификации multisite и базового варианта

Цель: один набор скриптов, где мультисайтовость — частный случай
конфигурации (`sites` с одним «локальным» сайтом = текущий базовый
вариант), а не отдельная ветка кода.

Порядок выбран от дешевого к дорогому: первые шаги — чистый рефакторинг
без изменения поведения, последние — переработка архитектуры.

## 1. Перевести базовый вариант на `_lib.inv` — ВЫПОЛНЕНО (низкий риск)

В корневых `_lib` и `usr.new` функции инвентори — копипаста curl-вызовов;
в `_lib.inv` то же самое собрано в единую `inventoryDataReq` + аккуратные
обертки (`inventoryGetUnusedIp`, `inventoryGetPinnedIp`,
`inventoryAttachUserIp`, `inventorySetIpInfo`).

- скопировать `_lib.inv` в корень, подключить в `usr.new`;
- удалить из корневых `_lib`/`usr.new` дублирующие функции
  (`inventoryGetUnusedIp`, `inventoryGetPinnedIp`, `attachUserIp`
  и inline-вызовы `net-ips/create|update`);
- поведение не меняется, тестируется сравнением CCD/инвентори до/после.

## 2. Унифицировать `usr.show` и `usr.revoke` — ВЫПОЛНЕНО (низкий риск)

Отличия сводятся к путям (`clients/revoked.crl` vs `crl/crl.pem`) и
поиску сертификатов в исторической раскладке `certs/*.pem`:

- пути CRL и revoked-папки вынести в `_config` с дефолтами базового варианта;
- поиск через `_list.sh` сделать fallback-ом внутри `usr.show`/`usr.revoke`
  (если файла нет по стандартному пути — искать по `certs/*.pem`);
- взять корневую версию `usr.revoke` (перемещение с таймстампом);
- после этого `_list.sh`/`_list_revoked.sh` удаляются из multisite.

## 3. Вынести генерацию CCD из `usr.new` в `usr.gen.ccd` — ВЫПОЛНЕНО (средний риск)

В multisite генерация CCD уже отдельный скрипт. Перенести это разбиение
в базовый вариант:

- корневой `usr.gen.ccd <user> [site]` без сайта работает как текущий
  CCD-блок `usr.new` (включая логику `previousVpnnet`/md5-миграции —
  ее же добавить и для мультисайта);
- `usr.new` вызывает `usr.gen.ccd`;
- обертка `_renew` в папке клиента продолжает работать как раньше.

## 4. Опциональные фичи генерации — ВЫПОЛНЕНО (средний риск)

Перенести из `usr.generate` в базовый `usr.new` под флагами `_config`:

- пароль на приватный ключ (`passLetters`, `passwd.txt`,
  `openssl genrsa -aes256`) — флаг `usePassKey=1`;
- дополнительный конфиг для OpenVPN Connect (`*_connect.ovpn`) — флаг
  `makeConnectConf=1`. В отличие от usr.generate без `key-direction 1`:
  сервер базового варианта использует двунаправленный tls-auth;
- 2FA-блок перенесен ранее (`use2fa=1` в корневом `usr.new`).

## 5. Доставка конфигов (`usr.send`) как опциональный модуль — ВЫПОЛНЕНО (средний риск)

`usr.send` не зависит от мультисайтовости — Nextcloud-шара + СМС полезны
и для одного сервера. Перенесен в корень; работает только если в
`_config` задан `nextcloudUrl` (СМС — при заданном `smsApiUrl`, иначе
только шара). Перебор сайтов заменен на общий список `*.ovpn` в папке
клиента (usr.generate сам удаляет неактуальные варианты), пароль и ключ
2FA шлются при наличии `passwd.txt`/`google.txt`. Попутно исправлен
незакавыченный URL с `&` (терялся `expand=private_phone`).

## 6. Обобщение мультисайтовости (высокий риск, финал) — ВЫПОЛНЕНО инстанс-моделью

Вместо `sites="local"` и site-центричной логики введена инстанс-модель
(см. `plans/migration-instance-model.md` — канон):

- `_lib`: `getInstances`/`inst_var` — инстанс как первоклассная сущность,
  дефолтный одиночный инстанс "local" падает на legacy-переменные
  (`srvaddr/port/proto/vpnnet/subnets/dns/use2fa`), CCD без суффикса;
- CCD на инстанс: `ccd.<instance>` (дефолтный — `ccd`); сеть/маршруты из
  `<instance>_lan/_routes`, IP закрепляется по `<instance>_inv_prefix`;
- `usr.new` генерирует конфиг на каждый инстанс с CCD (`<prefix>_<CN>_<instance>.ovpn`),
  при `auth_mode=2fa` — `auth-user-pass`/`auth-nocache`/`reneg-sec 0`;
- единый `usr.publish` (`<instance>_delivery=local|ssh`) вместо `usr.push`;
- `_ccd.check`/`normalTo2faIp`/`2faToNormalIp` удалены: режим — атрибут
  `auth_mode`, доступ — наличие `ccd.<instance>`; подсети инстансов
  независимы (ограничение /24 и совпадение третьего октета сняты);
- multisite/ как отдельная папка скриптов исчезла: остались одни корневые
  скрипты + разные `_config` (см. корневой `_config.sample`, блок `instances`).

Разовая миграция продовых данных multisite — `migrate-to-instances.sh`
(переименование `ccd.<site>` → `ccd.<site>`/`ccd.<site>-2fa`).

## 7. Reset для мультисайта — ВЫПОЛНЕНО

Корневой `_reset.sh` переписан под инстанс-модель: в одиночном режиме —
`server.conf` как раньше; при заданном `instances` — `server-<instance>.conf`
на каждый инстанс (`<instance>_lan/_port/_proto/_ccd_dir`), для 2FA —
`plugin openvpn-plugin-auth-pam.so openvpn` + `setenv OPENVPN_SERVER_NAME <instance>`.

## Не переносим (кандидаты на удаление)

- `_list_missing.sh`, `_update.old.sh` — одноразовые утилиты миграции из
  исторической CA-раскладки, в репозиторий не включены;
- `openssl.cnf` от TinyCA — не нужен, корневой `openssl.cnf` подходит
  для новых инсталляций.
