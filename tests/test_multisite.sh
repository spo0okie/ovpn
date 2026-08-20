#!/bin/bash
#тесты multisite: функции _lib, определение режима _ccd.check, генерация CCD
cd "$(dirname "$0")"
. ./helpers.sh

#развернуть multisite-скрипты в песочнице
function deployMulti() {
	newSandbox
	ms=$sandbox/ms
	mkdir -p $ms
	cp $REPO_DIR/multisite/_lib $REPO_DIR/multisite/_lib.inv \
	   $REPO_DIR/multisite/_ccd.check $REPO_DIR/multisite/usr.gen.ccd $ms/
	cat > $ms/_config <<CFG
prefix=tst
sites="mhk nn"
mhk_openvpn_lan=10.8.0.0/24
mhk_openvpn2fa_lan=10.108.0.0/24
nn_openvpn_lan=10.4.0.0/24
push_routes="10.10.0.0/16"
inventoryApiUrl=https://inventory.test.local/api
CFG
}

deployMulti
SCRIPTPATH=$ms
. $ms/_config
. $ms/_lib

echo "конвертация адресов между обычной и 2FA подсетью:"
assertEquals "normalTo2faIp" "10.108.0.7" "`normalTo2faIp 10.8.0.7 mhk`"
assertEquals "2faToNormalIp" "10.8.0.7" "`2faToNormalIp 10.108.0.7 mhk`"
assertEquals "сайт без 2FA-сети: адрес не меняется" "10.4.0.7" "`normalTo2faIp 10.4.0.7 nn`"

echo "getCcdIp:"
mkdir -p $ms/clients
ccdf=$sandbox/ccd.test
printf '#comment\nifconfig-push 10.8.0.7 255.255.255.0\npush "route 10.10.0.0 255.255.0.0"\n' > $ccdf
assertEquals "IP из CCD (комментарии пропущены)" "10.8.0.7" "`getCcdIp $ccdf`"
printf 'ifconfig-push 10.8.0.8 255.255.255.0\n' > $ccdf.disabled
assertEquals "приоритет отключенного CCD" "10.8.0.8" "`getCcdIp $ccdf`"

echo "getConfigUser:"
assertEquals "логин из первых двух полей" "ais-pupkin" "`getConfigUser ais-pupkin-notebook`"
assertEquals "логин с точкой - первое поле" "ivan.petrov" "`getConfigUser ivan.petrov-nb`"
mkdir -p $ms/clients/tst-boss-vip-laptop
echo "real.login" > $ms/clients/tst-boss-vip-laptop/username.txt
assertEquals "переопределение через username.txt" "real.login" "`getConfigUser boss-vip-laptop`"

echo "_ccd.check - определение режима подключения:"
u=$ms/clients/tst-u1
mkdir -p $u
echo "ifconfig-push 10.8.0.7 255.255.255.0" > $u/ccd.mhk
assertEquals "IP в обычной сети -> OVPN" "OVPN" "`$ms/_ccd.check u1 mhk`"
echo "ifconfig-push 10.108.0.7 255.255.255.0" > $u/ccd.mhk
assertEquals "IP в 2FA-сети -> OVPN2FA" "OVPN2FA" "`$ms/_ccd.check u1 mhk`"
assertEquals "нет CCD -> NONE" "NONE" "`$ms/_ccd.check u1 nn`"
echo "ifconfig-push 10.99.0.7 255.255.255.0" > $u/ccd.mhk
$ms/_ccd.check u1 mhk > /dev/null 2>&1
assertExitCode "чужая подсеть - ошибка" "10" "$?"

echo "_ccd.check - отключенный CCD:"
u=$ms/clients/tst-u2
mkdir -p $u
echo "ifconfig-push 10.8.0.7 255.255.255.0" > $u/ccd.mhk.disabled
assertEquals "без флага отключенный не виден" "NONE" "`$ms/_ccd.check u2 mhk`"
assertEquals "с флагом виден" "OVPN" "`$ms/_ccd.check u2 mhk 1`"

echo "usr.gen.ccd - выдача IP на сайте:"
deployMulti
mkdir -p $ms/clients/tst-u3	#папку клиента в реальном цикле создает usr.new
curlRoute "net-ips/search?name=ovpn-u3" '{"text_addr":"10.8.0.9"}'
( cd $ms && ./usr.gen.ccd u3 mhk ) > $sandbox/out.log 2>&1
rc=$?
ccd=$ms/clients/tst-u3/ccd.mhk
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "адрес сконвертирован в 2FA-сеть" $ccd "ifconfig-push 10.108.0.9 255.255.255.0"
assertFileContains "маршрут сети сайта" $ccd 'push "route 10.8.0.0 255.255.255.0"'
assertFileContains "общие маршруты" $ccd 'push "route 10.10.0.0 255.255.0.0"'

echo "usr.gen.ccd - существующий CCD не трогается:"
curlRoute "net-ips/search?name=ovpn-u3" '{"text_addr":"10.8.0.99"}'
( cd $ms && ./usr.gen.ccd u3 mhk ) > $sandbox/out.log 2>&1
assertFileContains "CCD не перегенерирован" $ccd "10.108.0.9"
assertFileNotContains "новый адрес не записан" $ccd "10.8.0.99"

echo "usr.gen.ccd - нет свободных IP - останов:"
deployMulti
mkdir -p $ms/clients/tst-u4
curlRoute "net-ips/search" '{"text_addr":null}'
curlRoute "net-ips/first-unused" '{"text_addr":null}'
( cd $ms && ./usr.gen.ccd u4 mhk ) > $sandbox/out.log 2>&1
assertExitCode "останов с кодом 10" "10" "$?"
assertFileMissing "CCD не создан" $ms/clients/tst-u4/ccd.mhk

summarize
