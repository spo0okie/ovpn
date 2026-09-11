#!/bin/bash
#тесты функций базовой _lib и _lib.inv
cd "$(dirname "$0")"
. ./helpers.sh

. $REPO_DIR/_lib
. $REPO_DIR/_lib.inv

echo "suffix2mask:"
assertEquals "/24" "192.168.0.0 255.255.255.0" "`suffix2mask 192.168.0.0/24`"
assertEquals "/32" "10.1.2.3 255.255.255.255" "`suffix2mask 10.1.2.3/32`"
assertEquals "/23" "192.168.236.0 255.255.254.0" "`suffix2mask 192.168.236.0/23`"
assertEquals "/22" "10.250.0.0 255.255.252.0" "`suffix2mask 10.250.0.0/22`"
assertEquals "/21" "192.168.208.0 255.255.248.0" "`suffix2mask 192.168.208.0/21`"
assertEquals "/16" "10.20.0.0 255.255.0.0" "`suffix2mask 10.20.0.0/16`"
assertEquals "/8" "10.0.0.0 255.0.0.0" "`suffix2mask 10.0.0.0/8`"
assertEquals "адрес без суффикса не меняется" "10.1.2.3" "`suffix2mask 10.1.2.3`"

echo "networkSuffix:"
assertEquals "выделение суффикса" "24" "`networkSuffix 192.168.0.0/24`"
assertEquals "суффикс /8" "8" "`networkSuffix 10.0.0.0/8`"

echo "инстанс-модель: getInstances и inst_var (одиночный режим, fallback):"
unset instances
assertEquals "без instances - один дефолтный инстанс" "local" "`getInstances`"
srvaddr=vpn.test.local
port=5100
vpnnet=192.168.77.0/24
subnets="10.20.0.0/16"
assertEquals "inst_var addr -> srvaddr" "vpn.test.local" "`inst_var local addr`"
assertEquals "inst_var port -> port" "5100" "`inst_var local port`"
assertEquals "inst_var lan -> vpnnet" "192.168.77.0/24" "`inst_var local lan`"
assertEquals "inst_var routes -> subnets" "10.20.0.0/16" "`inst_var local routes`"
assertEquals "inst_var auth_mode без use2fa -> normal" "normal" "`inst_var local auth_mode`"
use2fa=1
assertEquals "inst_var auth_mode с use2fa=1 -> 2fa" "2fa" "`inst_var local auth_mode`"
unset use2fa
assertEquals "inst_var delivery по умолчанию -> local" "local" "`inst_var local delivery`"
assertEquals "inst_var inv_prefix по умолчанию -> ovpn-" "ovpn-" "`inst_var local inv_prefix`"

echo "инстанс-модель: multi-instance ('-' -> '_', fallback на legacy-дефолты):"
instances="local local-2fa"
local_addr=ovpn.test.local
local_2fa_addr=ovpn2fa.test.local
local_2fa_auth_mode=2fa
assertEquals "getInstances - список из \$instances" "local local-2fa" "`getInstances`"
assertEquals "inst_var local addr - своя переменная" "ovpn.test.local" "`inst_var local addr`"
assertEquals "inst_var local-2fa addr - '-' -> '_'" "ovpn2fa.test.local" "`inst_var local-2fa addr`"
assertEquals "inst_var local-2fa auth_mode" "2fa" "`inst_var local-2fa auth_mode`"
assertEquals "inst_var local auth_mode не задан - fallback на дефолт normal" "normal" "`inst_var local auth_mode`"
assertEquals "inst_var local port не задан - fallback на legacy port" "5100" "`inst_var local port`"

echo "instFileSuffix: суффикс имён файлов инстанса:"
unset instances
assertEquals "вырожденный случай - суффикс пустой" "" "`instFileSuffix . local`"
instances="local local-2fa"
assertEquals "multi - ccd суффикс" ".local-2fa" "`instFileSuffix . local-2fa`"
assertEquals "multi - конфиг суффикс" "_local-2fa" "`instFileSuffix _ local-2fa`"
assertEquals "multi - server суффикс" "-local-2fa" "`instFileSuffix - local-2fa`"
unset instances
unset local_addr local_2fa_addr local_2fa_auth_mode

echo "getConfigCcd: суффикс инстанса:"
prefix=tst
ovpndir=/tmp/ovpn-test
unset instances
assertEquals "одиночный режим - ccd без суффикса" "/tmp/ovpn-test/clients/tst-u/ccd" "`getConfigCcd u`"
instances="local local-2fa"
assertEquals "multi - ccd.<instance>" "/tmp/ovpn-test/clients/tst-u/ccd.local-2fa" "`getConfigCcd u local-2fa`"

echo "getConfigCcd: переопределение ccd_suffix:"
main_ccd_suffix=""
main_2fa_ccd_suffix=".2fa"
assertEquals "ccd_suffix пустой - ccd без суффикса" "/tmp/ovpn-test/clients/tst-u/ccd" "`getConfigCcd u main`"
assertEquals "ccd_suffix .2fa" "/tmp/ovpn-test/clients/tst-u/ccd.2fa" "`getConfigCcd u main-2fa`"
assertEquals "ccd_suffix без переопределения - .local-2fa" "/tmp/ovpn-test/clients/tst-u/ccd.local-2fa" "`getConfigCcd u local-2fa`"
unset main_ccd_suffix main_2fa_ccd_suffix

echo "instConfSuffix: суффикс имени клиентского конфига:"
assertEquals "multi по умолчанию - _<instance>" "_main" "`instConfSuffix main`"
main_conf_suffix=""
main_2fa_conf_suffix="_2fa"
assertEquals "conf_suffix пустой - без суффикса" "" "`instConfSuffix main`"
assertEquals "conf_suffix _2fa ('-' -> '_')" "_2fa" "`instConfSuffix main-2fa`"
assertEquals "conf_suffix без переопределения - _local-2fa" "_local-2fa" "`instConfSuffix local-2fa`"
unset main_conf_suffix main_2fa_conf_suffix
unset instances
assertEquals "одиночный режим - без суффикса" "" "`instConfSuffix local`"

echo "_lib.inv: получение IP (через заглушку curl):"
newSandbox
export inventoryApiUrl=https://inventory.test.local/api

curlRoute "net-ips/search?name=ovpn-testuser" '{"id":7,"text_addr":"10.64.68.5","name":"ovpn-testuser"}'
curlRoute "net-ips/first-unused" '{"text_addr":"10.64.68.9"}'

assertEquals "pinned IP найден" "10.64.68.5" "`inventoryGetPinnedIp ovpn-testuser`"
assertEquals "pinned IP не найден -> null" "null" "`inventoryGetPinnedIp ovpn-nonexistent`"
assertEquals "первый свободный IP (без маски)" "10.64.68.9" "`inventoryGetUnusedIp 10.64.68.0/24`"

echo "_lib.inv: закрепление IP за конфигом (inventorySetIpInfo):"
newSandbox
curlRoute "net-ips/search?addr=10.64.68.5" '{"id":3,"text_addr":"10.64.68.5","name":"ovpn-testuser"}'
out=$sandbox/out.log

inventorySetIpInfo 10.64.68.5 ovpn-testuser > $out
assertFileContains "имя совпадает - без изменений" $out "уже закреплен"

inventorySetIpInfo 10.64.68.5 ovpn-otheruser > $out
assertFileContains "имя отличается - переименование" $out "переименован"
assertFileContains "переименование через PUT net-ips/3" $CURL_LOG "net-ips/3"

inventorySetIpInfo 10.64.68.77 ovpn-newuser > $out
assertFileContains "адрес не найден - создание" $out "закреплен за конфигом"
assertFileContains "создание через net-ips/create" $CURL_LOG "net-ips/create"

echo "_lib.inv: привязка IP к пользователю (inventoryAttachUserIp):"
newSandbox
curlRoute "users/search?login=user1" '{"id":5,"Login":"user1","ips":"10.64.68.5"}'
out=$sandbox/out.log

inventoryAttachUserIp nosuchuser 10.64.68.9 > $out
assertFileContains "пользователь не найден" $out "не найден"

inventoryAttachUserIp user1 10.64.68.5 > $out
assertFileContains "IP уже закреплен" $out "уже закреплен"

inventoryAttachUserIp user1 10.64.68.9 > $out
assertFileContains "новый IP закреплен" $out "закреплен за пользователем"
assertFileContains "обновление через PUT users/5" $CURL_LOG "users/5"

summarize
