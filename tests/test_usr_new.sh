#!/bin/bash
#тесты usr.new: генерация CCD, миграция подсетей, 2FA
#openssl не нужен: ключ/серт создаются фикстурами, скрипт их пропускает
cd "$(dirname "$0")"
. ./helpers.sh

#развернуть базовые скрипты в песочнице (ovpndir = папка скриптов, как на сервере)
function deployBase() {
	newSandbox
	ovpn=$sandbox/ovpn
	mkdir -p $ovpn
	cp $REPO_DIR/usr.new $REPO_DIR/_lib $ovpn/
	cat > $ovpn/_config <<CFG
org=TestOrg
prefix=tst
srvname=tst-server
srvaddr=vpn.test.local
proto=udp
port=1194
vpnnet=10.64.68.0/24
subnets="10.20.0.0/16 10.30.0.0/16"
dns="10.64.68.2"
ovpndir=$ovpn
sslconf=$ovpn/openssl.cnf
inventoryApiUrl=https://inventory.test.local/api
CFG
	echo "cipher AES-256-CBC" > $ovpn/server.conf
	echo "FAKE CA" > $ovpn/ca.pem
	echo "FAKE TA" > $ovpn/ta.key
}

#фикстуры пользователя: ключ и серт уже есть - openssl не вызывается
function makeUser() {
	userdir=$ovpn/clients/tst-$1
	mkdir -p $userdir
	echo "FAKE KEY" > $userdir/tst_$1.key
	echo "FAKE CERT" > $userdir/tst_$1.crt
}

function runUsrNew() { #пользователь [аргумент2]
	( cd $ovpn && ./usr.new "$@" ) > $sandbox/out.log 2>&1
	rc=$?
}


echo "новый пользователь, IP закреплен в инвентори:"
deployBase
makeUser testuser
curlRoute "net-ips/search?name=ovpn-testuser" '{"text_addr":"10.64.68.5"}'
runUsrNew testuser
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "CCD: закрепленный IP с маской" $userdir/ccd "ifconfig-push 10.64.68.5 255.255.255.0"
assertFileContains "CCD: маршрут vpn-сети" $userdir/ccd 'push "route 10.64.68.0 255.255.255.0"'
assertFileContains "CCD: маршрут подсети 1" $userdir/ccd 'push "route 10.20.0.0 255.255.0.0"'
assertFileContains "CCD: маршрут подсети 2" $userdir/ccd 'push "route 10.30.0.0 255.255.0.0"'
assertFileContains "конфиг: адрес сервера" $userdir/tst_testuser.ovpn "vpn.test.local"
assertFileContains "конфиг: cipher из server.conf" $userdir/tst_testuser.ovpn "cipher AES-256-CBC"
assertFileContains "конфиг: сертификат вложен" $userdir/tst_testuser.ovpn "FAKE CERT"
assertFileExists "обертка _renew создана" $userdir/_renew
assertFileMissing "google.txt без use2fa не создается" $userdir/google.txt
assertFileContains "IP отправлен в инвентори" $CURL_LOG "net-ips/create"

echo "IP не закреплен - берется первый свободный:"
deployBase
makeUser u2
curlRoute "net-ips/search?name=ovpn-u2" '{"text_addr":null}'
curlRoute "net-ips/first-unused" '{"text_addr":"10.64.68.9"}'
runUsrNew u2
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "CCD: свободный IP" $userdir/ccd "ifconfig-push 10.64.68.9 255.255.255.0"

echo "IP получить неоткуда - останов:"
deployBase
makeUser u3
curlRoute "net-ips/search?name=ovpn-u3" '{"text_addr":null}'
curlRoute "net-ips/first-unused" '{"text_addr":null}'
runUsrNew u3
assertExitCode "останов с кодом 10" "10" "$rc"
assertFileMissing "CCD не создан" $userdir/ccd

echo "повторный запуск с актуальным CCD - без изменений:"
deployBase
makeUser u4
curlRoute "net-ips/search?name=ovpn-u4" '{"text_addr":"10.64.68.5"}'
runUsrNew u4
cp $userdir/ccd $sandbox/ccd.before
runUsrNew u4
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "сообщение 'no CCD changes'" $sandbox/out.log "no CCD changes"
assertEquals "CCD не изменился" "" "`diff $sandbox/ccd.before $userdir/ccd`"
assertFileMissing "ccd.new не создан" $userdir/ccd.new

echo "миграция: CCD старого образца обновляется до нового:"
deployBase
makeUser u5
cat >> $ovpn/_config <<CFG
previousVpnnet=10.60.0.0/24
previousSubnets="10.20.0.0/16"
CFG
curlRoute "net-ips/search?name=ovpn-u5" '{"text_addr":"10.64.68.5"}'
cat > $userdir/ccd <<OLD
ifconfig-push 10.64.68.5 255.255.255.0
push "route 10.60.0.0 255.255.255.0"
push "route 10.20.0.0 255.255.0.0"
OLD
runUsrNew u5
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "сообщение об обновлении" $sandbox/out.log "CCD version updating"
assertFileContains "новый маршрут vpn-сети" $userdir/ccd 'push "route 10.64.68.0 255.255.255.0"'
assertFileContains "добавленная подсеть" $userdir/ccd 'push "route 10.30.0.0 255.255.0.0"'
assertFileNotContains "старый маршрут убран" $userdir/ccd 'push "route 10.60.0.0 255.255.255.0"'

echo "миграция: кастомный CCD не трогаем:"
deployBase
makeUser u6
cat >> $ovpn/_config <<CFG
previousVpnnet=10.60.0.0/24
previousSubnets="10.20.0.0/16"
CFG
curlRoute "net-ips/search?name=ovpn-u6" '{"text_addr":"10.64.68.5"}'
echo "ifconfig-push 10.99.99.99 255.255.255.0" > $userdir/ccd
runUsrNew u6
assertFileContains "предупреждение о кастомном CCD" $sandbox/out.log "custom CCD"
assertFileContains "CCD не тронут" $userdir/ccd "10.99.99.99"
assertFileNotContains "CCD не перезаписан" $userdir/ccd "10.64.68.5"
assertFileExists "рядом положен ccd.new" $userdir/ccd.new
assertFileExists "рядом положен ccd.old" $userdir/ccd.old

echo "noupdate: существующий CCD не трогается:"
deployBase
makeUser u7
echo "ifconfig-push 10.99.99.99 255.255.255.0" > $userdir/ccd
runUsrNew u7 noupdate
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "CCD не тронут" $userdir/ccd "10.99.99.99"
assertFileMissing "ccd.new не создан" $userdir/ccd.new

echo "use2fa=1: генерируется секрет google-authenticator:"
deployBase
makeUser u8
echo "use2fa=1" >> $ovpn/_config
curlRoute "net-ips/search?name=ovpn-u8" '{"text_addr":"10.64.68.5"}'
runUsrNew u8
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "секрет создан" $userdir/google.txt "TESTSECRET234567"
echo "SECRET_KEEP" > $userdir/google.txt
runUsrNew u8
assertFileContains "повторный запуск не перегенерирует секрет" $userdir/google.txt "SECRET_KEEP"

summarize
