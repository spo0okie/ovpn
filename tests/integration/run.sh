#!/bin/bash
#интеграционные прогоны в Docker: настоящие openssl/openvpn, реальный туннель
#запуск: bash tests/integration/run.sh
#требуется Docker (Docker Desktop / WSL2). Первый прогон долгий (dhparam 4096)

cd "$(dirname "$0")"
. ../helpers.sh

export MSYS_NO_PATHCONV=1	#git-bash: не превращать /shared/... в C:/...

INSIDE=/repo/tests/integration/inside

function srv() {	#выполнить в контейнере server
	docker compose exec -T server bash -c "$*"
}
function srv2() {	#выполнить в контейнере server2 (multi-instance)
	docker compose exec -T server2 bash -c "$*"
}
function cli() {	#выполнить в контейнере client
	docker compose exec -T client bash "$@"
}

#WITH_INVENTORY=0 - пропустить сценарий с настоящей инвентори (arms)
WITH_INVENTORY=${WITH_INVENTORY:-1}
COMPOSE_PROFILES=""
[ "$WITH_INVENTORY" == "1" ] && COMPOSE_PROFILES="--profile inventory"

function teardown() {
	docker compose $COMPOSE_PROFILES down -v --remove-orphans >/dev/null 2>&1
}
trap teardown EXIT

echo "=== поднимаю окружение ==="
docker compose $COMPOSE_PROFILES up -d --build --quiet-pull 2>&1 | tail -3 || { echo "FAIL: docker compose up"; exit 1; }


echo "== 1. Инициализация сервера (_reset.sh + запуск openvpn)"
srv "bash $INSIDE/setup-server.sh"
assertExitCode "инициализация и старт сервера" "0" "$?"
[ $failures -gt 0 ] && { echo "сервер не поднялся - дальше смысла нет"; summarize; }


echo "== 2. Генерация пользователя и подключение"
srv "cd /etc/openvpn && ./usr.new user1 >/dev/null && ./usr.enable user1"
assertExitCode "usr.new + usr.enable" "0" "$?"

srv "cd /etc/openvpn && openssl verify -CAfile ca.pem clients/tst-user1/tst_user1.crt"
assertExitCode "сертификат подписан нашим CA" "0" "$?"

srv "cd /etc/openvpn/clients/tst-user1 && \
	[ \"\$(openssl x509 -noout -modulus -in tst_user1.crt)\" = \"\$(openssl rsa -noout -modulus -in tst_user1.key)\" ]"
assertExitCode "ключ соответствует сертификату" "0" "$?"

srv "cd /etc/openvpn/clients/tst-user1 && grep -q '<ca>' tst_user1.ovpn && grep -q '<cert>' tst_user1.ovpn && grep -q '<key>' tst_user1.ovpn && grep -q '<tls-auth>' tst_user1.ovpn"
assertExitCode "конфиг содержит все inline-секции" "0" "$?"

#серийник запоминаем до отзыва (потом папка уедет в revoked)
user1serial=$(srv "openssl x509 -noout -serial -in /etc/openvpn/clients/tst-user1/tst_user1.crt | cut -d= -f2" | tr -d ' \r\n')

srv "cd /etc/openvpn && ./usr.show user1 | grep -q 'CN = user1'"
assertExitCode "usr.show показывает сертификат пользователя" "0" "$?"

srv "cd /etc/openvpn && ./usr.show serv | grep -q 'Certificate:'"
assertExitCode "usr.show serv находит серверный серт (.cert от reset)" "0" "$?"

srv "cp /etc/openvpn/clients/tst-user1/tst_user1.ovpn /shared/"
cli $INSIDE/connect.sh /shared/tst_user1.ovpn success
assertExitCode "клиент поднял туннель и пингует сервер" "0" "$?"


echo "== 3. Отзыв пользователя"
srv "cd /etc/openvpn && ./usr.revoke user1"
assertExitCode "usr.revoke" "0" "$?"

srv "ls /etc/openvpn/clients/revoked/ | grep -q '^tst-user1\.'"
assertExitCode "папка клиента уехала в revoked с таймстампом" "0" "$?"

srv "openssl crl -noout -text -in /etc/openvpn/clients/revoked.crl | grep -q '$user1serial'"
assertExitCode "серийник в CRL" "0" "$?"

cli $INSIDE/connect.sh /shared/tst_user1.ovpn fail
assertExitCode "отозванный конфиг отвергается сервером" "0" "$?"

srv "cd /etc/openvpn && ./usr.show user1 | grep -q 'USER IS REVOKED'"
assertExitCode "usr.show видит отозванного (папка с таймстампом)" "0" "$?"

#историческая раскладка: сертификат в legacyCertsDir без папки клиента
srv "echo 'legacyCertsDir=./legacy-certs' >> /etc/openvpn/_config && cd /etc/openvpn && ./usr.new legacy1 >/dev/null && mkdir -p legacy-certs && cp clients/tst-legacy1/tst_legacy1.crt legacy-certs/legacy1.pem && rm -rf clients/tst-legacy1"
assertExitCode "подготовлен сертификат исторической раскладки" "0" "$?"

srv "cd /etc/openvpn && ./usr.show legacy1 | grep -q 'CN = legacy1'"
assertExitCode "usr.show находит сертификат в legacyCertsDir" "0" "$?"

srv "cd /etc/openvpn && ./usr.revoke legacy1 >/dev/null"
assertExitCode "usr.revoke отзывает сертификат исторической раскладки" "0" "$?"

srv "[ -e /etc/openvpn/legacy-certs/revoked/legacy1.pem ]"
assertExitCode "сертификат убран в legacyCertsDir/revoked" "0" "$?"

srv "cd /etc/openvpn && ./usr.show legacy1 | grep -q 'USER IS REVOKED'"
assertExitCode "usr.show видит отозванного в исторической раскладке" "0" "$?"

srv "cd /etc/openvpn && ./usr.revoke nosuchuser >/dev/null; [ \$? -eq 10 ]"
assertExitCode "отзыв несуществующего пользователя дает код 10" "0" "$?"


echo "== 4. Массовая генерация (10 пользователей)"
srv "cd /etc/openvpn && for i in \$(seq -w 1 10); do ./usr.new mass\$i >/dev/null && ./usr.enable mass\$i >/dev/null || exit 1; done"
assertExitCode "создание 10 пользователей" "0" "$?"

nvalid=$(srv "cd /etc/openvpn && for i in \$(seq -w 1 10); do openssl verify -CAfile ca.pem clients/tst-mass\$i/tst_mass\$i.crt >/dev/null 2>&1 && echo ok; done | wc -l")
assertEquals "все 10 сертификатов валидны" "10" "$(echo $nvalid | tr -d ' \r')"

nserial=$(srv "cd /etc/openvpn && for i in \$(seq -w 1 10); do openssl x509 -noout -serial -in clients/tst-mass\$i/tst_mass\$i.crt; done | sort -u | wc -l")
assertEquals "серийники не пересекаются" "10" "$(echo $nserial | tr -d ' \r')"

srv "cp /etc/openvpn/clients/tst-mass*/tst_mass*.ovpn /shared/"
connected=0
for i in $(seq -w 1 10); do
	cli $INSIDE/connect.sh /shared/tst_mass$i.ovpn success >/dev/null && connected=$((connected+1))
done
assertEquals "все 10 конфигов поднимают туннель" "10" "$connected"


echo "== 5. Массовое добавление сетей в CCD"
#кастомный CCD до смены конфигурации
srv "cd /etc/openvpn && ./usr.new custom1 >/dev/null && echo 'ifconfig-push 192.168.77.200 255.255.255.0' > clients/tst-custom1/ccd"
assertExitCode "подготовлен пользователь с кастомным CCD" "0" "$?"

#меняем состав подсетей (previous* = старый состав)
srv "cat >> /etc/openvpn/_config <<'EOF'
subnets=\"172.20.0.0/16 172.21.0.0/16\"
previousVpnnet=192.168.77.0/24
previousSubnets=\"172.20.0.0/16\"
EOF"

#обход всех пользователей (как в README)
srv "cd /etc/openvpn && for f in ./clients/tst-*; do \$f/_renew >/dev/null || exit 1; done"
assertExitCode "обход _renew по всем пользователям" "0" "$?"

srv "grep -qF 'route 172.21.0.0 255.255.0.0' /etc/openvpn/clients/tst-mass01/ccd"
assertExitCode "стандартный CCD обновился (новый маршрут)" "0" "$?"

srv "grep -qF '192.168.77.200' /etc/openvpn/clients/tst-custom1/ccd && ! grep -qF '172.21.0.0' /etc/openvpn/clients/tst-custom1/ccd"
assertExitCode "кастомный CCD не тронут" "0" "$?"

srv "[ -s /etc/openvpn/clients/tst-custom1/ccd.new ] && [ -s /etc/openvpn/clients/tst-custom1/ccd.old ]"
assertExitCode "рядом с кастомным лежат ccd.new/ccd.old" "0" "$?"

#клиент реально получает новый маршрут
cli $INSIDE/connect.sh /shared/tst_mass01.ovpn success "172.21.0.0/16"
assertExitCode "клиенту пушится добавленный маршрут" "0" "$?"


echo "== 6. Опциональные фичи генерации (usePassKey, makeConnectConf)"
srv "printf 'usePassKey=1
makeConnectConf=1
' >> /etc/openvpn/_config"
srv "cd /etc/openvpn && ./usr.new secure1 >/dev/null && ./usr.enable secure1 >/dev/null"
assertExitCode "usr.new с паролем на ключ" "0" "$?"

srv "grep -q ENCRYPTED /etc/openvpn/clients/tst-secure1/tst_secure1.key"
assertExitCode "приватный ключ зашифрован" "0" "$?"

srv "cd /etc/openvpn/clients/tst-secure1 && openssl rsa -in tst_secure1.key -passin file:passwd.txt -noout"
assertExitCode "ключ читается паролем из passwd.txt" "0" "$?"

srv "cp /etc/openvpn/clients/tst-secure1/tst_secure1.ovpn /etc/openvpn/clients/tst-secure1/tst_secure1_connect.ovpn /shared/ && cp /etc/openvpn/clients/tst-secure1/passwd.txt /shared/secure1.pass"
cli $INSIDE/connect.sh /shared/tst_secure1.ovpn success "" /shared/secure1.pass
assertExitCode "туннель с зашифрованным ключом (askpass)" "0" "$?"

cli $INSIDE/connect.sh /shared/tst_secure1_connect.ovpn success "" /shared/secure1.pass
assertExitCode "конфиг для OpenVPN Connect поднимает туннель" "0" "$?"

srv "sed -i '/usePassKey/d;/makeConnectConf/d' /etc/openvpn/_config"


echo "== 7. Доставка конфигов по почте (mailpit)"
srv "printf 'mailSmtpUrl=smtp://mailpit:1025
mailFrom=vpn@test.local
' >> /etc/openvpn/_config"
srv "cd /etc/openvpn && ./usr.send secure1 secure1@test.local"
assertExitCode "usr.send отправил письмо" "0" "$?"

srv "curl -s http://mailpit:8025/api/v1/messages | jq -e '.total >= 1' >/dev/null"
assertExitCode "письмо дошло до SMTP-сервера" "0" "$?"

mailid=$(srv "curl -s http://mailpit:8025/api/v1/messages | jq -r '.messages[0].ID'" | tr -d ' 
')
srv "curl -s http://mailpit:8025/api/v1/message/$mailid | jq -r '.To[0].Address' | grep -q secure1@test.local"
assertExitCode "получатель верный" "0" "$?"

srv "curl -s http://mailpit:8025/api/v1/message/$mailid | jq -r '.Attachments[].FileName' | grep -q '^tst_secure1.ovpn$'"
assertExitCode "конфиг во вложении" "0" "$?"

partid=$(srv "curl -s http://mailpit:8025/api/v1/message/$mailid | jq -r '.Attachments[] | select(.FileName==\"tst_secure1.ovpn\").PartID'" | tr -d ' 
')
srv "curl -s http://mailpit:8025/api/v1/message/$mailid/part/$partid -o /tmp/att.ovpn && diff /tmp/att.ovpn /etc/openvpn/clients/tst-secure1/tst_secure1.ovpn"
assertExitCode "вложение побайтово совпадает с конфигом" "0" "$?"

srv "sed -i '/mailSmtpUrl/d;/mailFrom/d' /etc/openvpn/_config"


if [ "$WITH_INVENTORY" == "1" ]; then
	echo "== 8. Интеграция с настоящей инвентори (arms)"
	srv "bash $INSIDE/seed-inventory.sh"
	assertExitCode "инвентори поднялась и засидирована" "0" "$?"

	srv "echo 'inventoryApiUrl=http://arms-app:8088/index.php/api' >> /etc/openvpn/_config"

	srv "cd /etc/openvpn && ./usr.new inv1 >/dev/null && ./usr.enable inv1 >/dev/null"
	assertExitCode "usr.new с инвентори" "0" "$?"

	addr1=$(srv "grep ifconfig-push /etc/openvpn/clients/tst-inv1/ccd | cut -d' ' -f2" | tr -d ' \r\n')
	assertEquals "inv1 получил адрес из тестовой сети" "192.168.77" "$(echo $addr1 | cut -d. -f1-3)"
	[ -n "$addr1" ] && [ "$addr1" != "192.168.77.1" ]
	assertExitCode "адрес не конфликтует с адресом сервера" "0" "$?"

	srv "cd /etc/openvpn && ./usr.new inv2 >/dev/null"
	addr2=$(srv "grep ifconfig-push /etc/openvpn/clients/tst-inv2/ccd | cut -d' ' -f2" | tr -d ' \r\n')
	[ -n "$addr2" ] && [ "$addr1" != "$addr2" ]
	assertExitCode "второй пользователь получил другой адрес ($addr1 / $addr2)" "0" "$?"

	#перегенерация: закрепленный за конфигом адрес не меняется
	srv "cd /etc/openvpn && rm /etc/openvpn/clients/tst-inv1/ccd && ./usr.new inv1 >/dev/null"
	addr1b=$(srv "grep ifconfig-push /etc/openvpn/clients/tst-inv1/ccd | cut -d' ' -f2" | tr -d ' \r\n')
	assertEquals "закрепленный адрес стабилен при перегенерации" "$addr1" "$addr1b"

	#IP привязан к пользователю в инвентори
	srv "curl -s 'http://arms-app:8088/index.php/api/users/search?login=inv1' | jq -r .ips | grep -qF '$addr1'"
	assertExitCode "IP закреплен за пользователем в инвентори" "0" "$?"

	#и туннель реально поднимается с выданным инвентори адресом
	srv "cp /etc/openvpn/clients/tst-inv1/tst_inv1.ovpn /shared/"
	cli $INSIDE/connect.sh /shared/tst_inv1.ovpn success "src $addr1"
	assertExitCode "клиент поднял туннель с адресом из инвентори" "0" "$?"
fi

echo "== 9. Один хост, два инстанса (обычный + 2FA)"
srv2 "bash $INSIDE/setup-multiinstance.sh"
assertExitCode "инициализация двух инстансов" "0" "$?"
[ $failures -gt 0 ] && { echo "server2 не поднялся - пропускаю остальное"; summarize; }

srv2 "cd /etc/openvpn && ./usr.new multi1 >/dev/null && ./usr.publish multi1"
assertExitCode "usr.new + usr.publish (2 инстанса)" "0" "$?"

srv2 "cd /etc/openvpn && grep -qF 'auth-user-pass' clients/tst-multi1/tst_multi1_local-2fa.ovpn"
assertExitCode "2FA-конфиг содержит auth-user-pass" "0" "$?"

srv2 "cd /etc/openvpn && ! grep -qF 'auth-user-pass' clients/tst-multi1/tst_multi1_local.ovpn"
assertExitCode "обычный конфиг без auth-user-pass" "0" "$?"

srv2 "cd /etc/openvpn && [ -e ccd/multi1 ] && [ -e ccd-2fa/multi1 ]"
assertExitCode "CCD опубликованы в раздельные каталоги" "0" "$?"

srv2 "cp /etc/openvpn/clients/tst-multi1/tst_multi1_local.ovpn /shared/"
cli $INSIDE/connect.sh /shared/tst_multi1_local.ovpn success "" "" 192.168.88.1
assertExitCode "обычный конфиг поднимает туннель (server2)" "0" "$?"

summarize
