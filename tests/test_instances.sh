#!/bin/bash
#тесты инстанс-модели: CCD на инстанс, конфиги, publish (local/ssh), inv_prefix
cd "$(dirname "$0")"
. ./helpers.sh

#развернуть скрипты в песочнице с multi-instance конфигурацией
function deployInstances() {
	newSandbox
	ovpn=$sandbox/ovpn
	mkdir -p $ovpn
	cp $REPO_DIR/usr.new $REPO_DIR/usr.gen.ccd $REPO_DIR/usr.publish \
	   $REPO_DIR/usr.enable $REPO_DIR/usr.disable $REPO_DIR/usr.ccd2env \
	   $REPO_DIR/_lib $REPO_DIR/_lib.inv $ovpn/
	cat > $ovpn/_config <<CFG
org=TestOrg
prefix=tst
srvname=tst-server
ovpndir=$ovpn
sslconf=$ovpn/openssl.cnf
inventoryApiUrl=https://inventory.test.local/api
cipher=AES-256-CBC
instances="local local-2fa"
local_addr=vpn.test.local
local_port=1194
local_proto=udp
local_lan=10.32.0.0/24
local_routes="10.40.0.0/16"
local_auth_mode=normal
local_ccd_dir=$ovpn/ccd
local_delivery=local
local_inv_prefix="ovpn-"
local_2fa_addr=vpn2.test.local
local_2fa_port=1196
local_2fa_proto=udp
local_2fa_lan=10.132.0.0/24
local_2fa_routes="10.40.0.0/16"
local_2fa_auth_mode=2fa
local_2fa_ccd_dir=$ovpn/ccd-2fa
local_2fa_delivery=local
local_2fa_inv_prefix="ovpn2fa-"
CFG
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


echo "usr.gen.ccd - выдача IP на обычный инстанс:"
deployInstances
mkdir -p $ovpn/clients/tst-u1
curlRoute "net-ips/search?name=ovpn-u1" '{"text_addr":"10.32.0.5"}'
( cd $ovpn && ./usr.gen.ccd u1 local ) > $sandbox/out.log 2>&1
rc=$?
ccd=$ovpn/clients/tst-u1/ccd.local
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "адрес в сети инстанса" $ccd "ifconfig-push 10.32.0.5 255.255.255.0"
assertFileContains "маршрут сети инстанса" $ccd 'push "route 10.32.0.0 255.255.255.0"'
assertFileContains "маршруты инстанса" $ccd 'push "route 10.40.0.0 255.255.0.0"'
assertFileContains "IP ищется по inv_prefix обычного инстанса" $CURL_LOG "name=ovpn-u1"

echo "usr.gen.ccd - 2FA-инстанс со своим inv_prefix и подсетью:"
deployInstances
mkdir -p $ovpn/clients/tst-u2
curlRoute "net-ips/search?name=ovpn2fa-u2" '{"text_addr":"10.132.0.7"}'
( cd $ovpn && ./usr.gen.ccd u2 local-2fa ) >/dev/null 2>&1
ccd=$ovpn/clients/tst-u2/ccd.local-2fa
assertFileContains "адрес в 2FA-сети" $ccd "ifconfig-push 10.132.0.7 255.255.255.0"
assertFileContains "маршрут 2FA-сети" $ccd 'push "route 10.132.0.0 255.255.255.0"'
assertFileContains "IP ищется по inv_prefix 2FA-инстанса" $CURL_LOG "name=ovpn2fa-u2"

echo "usr.gen.ccd - нет свободных IP - останов:"
deployInstances
mkdir -p $ovpn/clients/tst-u3
curlRoute "net-ips/search" '{"text_addr":null}'
curlRoute "net-ips/first-unused" '{"text_addr":null}'
( cd $ovpn && ./usr.gen.ccd u3 local ) >/dev/null 2>&1
assertExitCode "останов с кодом 10" "10" "$?"
assertFileMissing "CCD не создан" $ovpn/clients/tst-u3/ccd.local

echo "usr.gen.ccd - миграция подсети инстанса:"
deployInstances
mkdir -p $ovpn/clients/tst-u4
curlRoute "net-ips/search?name=ovpn-u4" '{"text_addr":"10.32.0.9"}'
cat >> $ovpn/_config <<CFG
local_previous_lan=10.32.0.0/24
local_previous_routes="10.40.0.0/16"
CFG
cat > $ovpn/clients/tst-u4/ccd.local <<OLD
ifconfig-push 10.32.0.9 255.255.255.0
push "route 10.32.0.0 255.255.255.0"
push "route 10.40.0.0 255.255.0.0"
OLD
( cd $ovpn && ./usr.gen.ccd u4 local ) > $sandbox/out.log 2>&1
assertFileContains "без изменений (актуальный CCD)" $sandbox/out.log "no CCD changes"

echo "usr.new - конфиги на каждый инстанс:"
deployInstances
makeUser u5
curlRoute "net-ips/search?name=ovpn-u5" '{"text_addr":"10.32.0.11"}'
curlRoute "net-ips/search?name=ovpn2fa-u5" '{"text_addr":"10.132.0.11"}'
( cd $ovpn && ./usr.new u5 ) > $sandbox/out.log 2>&1
rc=$?
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "обычный конфиг: remote" $ovpn/clients/tst-u5/tst_u5_local.ovpn "vpn.test.local"
assertFileContains "обычный конфиг: порт" $ovpn/clients/tst-u5/tst_u5_local.ovpn "1194"
assertFileNotContains "обычный конфиг без auth-user-pass" $ovpn/clients/tst-u5/tst_u5_local.ovpn "auth-user-pass"
assertFileContains "2FA-конфиг: remote" $ovpn/clients/tst-u5/tst_u5_local-2fa.ovpn "vpn2.test.local"
assertFileContains "2FA-конфиг: порт" $ovpn/clients/tst-u5/tst_u5_local-2fa.ovpn "1196"
assertFileContains "2FA-конфиг: auth-user-pass" $ovpn/clients/tst-u5/tst_u5_local-2fa.ovpn "auth-user-pass"
assertFileContains "2FA-конфиг: auth-nocache" $ovpn/clients/tst-u5/tst_u5_local-2fa.ovpn "auth-nocache"
assertFileContains "2FA-конфиг: reneg-sec 0" $ovpn/clients/tst-u5/tst_u5_local-2fa.ovpn "reneg-sec 0"
assertFileContains "секрет 2FA создан" $ovpn/clients/tst-u5/google.txt "TESTSECRET234567"

echo "usr.new - conf_suffix инстанса:"
deployInstances
makeUser cs1
cat >> $ovpn/_config <<CFG
local_conf_suffix=""
local_2fa_conf_suffix="_2fa"
CFG
curlRoute "net-ips/search?name=ovpn-cs1" '{"text_addr":"10.32.0.12"}'
curlRoute "net-ips/search?name=ovpn2fa-cs1" '{"text_addr":"10.132.0.12"}'
( cd $ovpn && ./usr.new cs1 ) > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileExists "пустой суффикс - конфиг без суффикса" $ovpn/clients/tst-cs1/tst_cs1.ovpn
assertFileExists "свой суффикс 2FA-инстанса" $ovpn/clients/tst-cs1/tst_cs1_2fa.ovpn
assertFileMissing "конфиг с дефолтным суффиксом не создан" $ovpn/clients/tst-cs1/tst_cs1_local-2fa.ovpn

echo "usr.publish - local: симлинк в ccd_dir инстанса:"
deployInstances
u=$ovpn/clients/tst-u6
mkdir -p $u
printf 'ifconfig-push 10.32.0.13 255.255.255.0\n' > $u/ccd.local
( cd $ovpn && ./usr.publish u6 local ) > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileExists "опубликованный CCD в ccd_dir" $ovpn/ccd/u6
assertFileContains "содержимое CCD опубликовано" $ovpn/ccd/u6 "ifconfig-push 10.32.0.13"

echo "usr.publish - disable: симлинк снят, CCD в .disabled:"
( cd $ovpn && ./usr.publish u6 local disable ) > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileMissing "симлинк удален" $ovpn/ccd/u6
assertFileExists "ccd стал disabled" $u/ccd.local.disabled

echo "usr.publish - ssh: push CCD и 2FA-секрета на удаленный инстанс:"
deployInstances
sed -i 's#local_2fa_delivery=local#local_2fa_delivery=ssh#' $ovpn/_config
sed -i 's#local_2fa_ccd_dir=.*#local_2fa_ccd_dir=/etc/openvpn/ccd#' $ovpn/_config
cat >> $ovpn/_config <<CFG
local_2fa_ssh_host=ovpn2fa.contoso.local
local_2fa_ssh_key=/root/.ssh/key
local_2fa_gauth_dir=/etc/google-auth
CFG
u=$ovpn/clients/tst-u7
mkdir -p $u
printf 'ifconfig-push 10.132.0.15 255.255.255.0\n' > $u/ccd.local-2fa
echo "GOOGLESECRET" > $u/google.txt
( cd $ovpn && ./usr.publish u7 local-2fa ) > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "ssh на нужный хост" $SSH_LOG "root@ovpn2fa.contoso.local"
assertFileContains "ssh пушит CCD" $SSH_LOG "ifconfig-push 10.132.0.15"
assertFileContains "ssh пушит 2FA-секрет" $SSH_LOG "GOOGLESECRET"
assertFileContains "секрет в gauth_dir" $SSH_LOG "/etc/google-auth/u7/.google_auth"

echo "usr.publish - ssh disable: remote CCD переименован в _OFF:"
( cd $ovpn && ./usr.publish u7 local-2fa disable ) > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "ssh выключает (mv _OFF)" $SSH_LOG "mv -f /etc/openvpn/ccd/u7 /etc/openvpn/ccd/u7_OFF"

echo "usr.enable/usr.disable без инстанса - цикл по всем:"
deployInstances
u=$ovpn/clients/tst-u8
mkdir -p $u
printf 'ifconfig-push 10.32.0.17 255.255.255.0\n' > $u/ccd.local
printf 'ifconfig-push 10.132.0.17 255.255.255.0\n' > $u/ccd.local-2fa
( cd $ovpn && ./usr.enable u8 ) > $sandbox/out.log 2>&1
assertExitCode "включено на всех инстансах - код 0" "0" "$?"
assertFileExists "симлинк обычного инстанса" $ovpn/ccd/u8
assertFileExists "симлинк 2FA-инстанса" $ovpn/ccd-2fa/u8
( cd $ovpn && ./usr.disable u8 ) > $sandbox/out.log 2>&1
assertExitCode "отключено на всех инстансах - код 0" "0" "$?"
assertFileMissing "симлинк обычного инстанса снят" $ovpn/ccd/u8
assertFileMissing "симлинк 2FA-инстанса снят" $ovpn/ccd-2fa/u8

echo "usr.enable без инстанса - ошибка не на последнем инстансе не теряется:"
deployInstances
u=$ovpn/clients/tst-ue1
mkdir -p $u
printf 'ifconfig-push 10.132.0.19 255.255.255.0\n' > $u/ccd.local-2fa
( cd $ovpn && ./usr.enable ue1 ) > $sandbox/out.log 2>&1
assertExitCode "нет CCD на local - ненулевой код" "1" "$?"
assertFileContains "причина в выводе" $sandbox/out.log "нет CCD для ue1@local"
assertFileExists "остальные инстансы всё равно включены" $ovpn/ccd-2fa/ue1

echo "одиночный режим: дефолтный инстанс без суффикса CCD:"
newSandbox
ovpn=$sandbox/ovpn
mkdir -p $ovpn
cp $REPO_DIR/usr.gen.ccd $REPO_DIR/_lib $REPO_DIR/_lib.inv $ovpn/
cat > $ovpn/_config <<CFG
prefix=tst
ovpndir=$ovpn
vpnnet=10.64.68.0/24
subnets="10.20.0.0/16"
inventoryApiUrl=https://inventory.test.local/api
CFG
mkdir -p $ovpn/clients/tst-u9
curlRoute "net-ips/search?name=ovpn-u9" '{"text_addr":"10.64.68.15"}'
( cd $ovpn && ./usr.gen.ccd u9 ) >/dev/null 2>&1
assertFileExists "CCD без суффикса (ccd)" $ovpn/clients/tst-u9/ccd
assertFileMissing "нет ccd.local в одиночном режиме" $ovpn/clients/tst-u9/ccd.local

echo "usr.ccd2env - вывод IP из CCD всех инстансов:"
deployInstances
mkdir -p $ovpn/ccd $ovpn/ccd-2fa
printf 'ifconfig-push 10.32.0.50 255.255.255.0\n' > $ovpn/ccd/u10
printf 'ifconfig-push 10.132.0.51 255.255.255.0\n' > $ovpn/ccd-2fa/u10
printf 'ifconfig-push 10.32.0.52 255.255.255.0\n' > $ovpn/ccd/u11
out=$sandbox/ccd.env
( cd $ovpn && ./usr.ccd2env $out ) >/dev/null 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "local инстанс: пользователь u10" $out "local_u10=10.32.0.50"
assertFileContains "2fa инстанс: пользователь u10" $out "local_2fa_u10=10.132.0.51"
assertFileContains "local инстанс: пользователь u11" $out "local_u11=10.32.0.52"
assertFileContains "заголовок bash-файла" $out "#!/bin/bash"

echo "usr.ccd2env - вывод в stdout:"
deployInstances
mkdir -p $ovpn/ccd
printf 'ifconfig-push 10.32.0.60 255.255.255.0\n' > $ovpn/ccd/u12
out=$(cd $ovpn && ./usr.ccd2env)
assertExitCode "успешное завершение" "0" "${PIPESTATUS[0]}"
assertContains "stdout: local_u12" "$out" "local_u12=10.32.0.60"
assertNotContains "stdout без заголовка" "$out" "#!/bin/bash"

summarize
