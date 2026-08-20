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
function cli() {	#выполнить в контейнере client
	docker compose exec -T client bash "$@"
}

function teardown() {
	docker compose down -v --remove-orphans >/dev/null 2>&1
}
trap teardown EXIT

echo "=== поднимаю окружение ==="
docker compose up -d --build --quiet-pull 2>&1 | tail -3 || { echo "FAIL: docker compose up"; exit 1; }


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

summarize
