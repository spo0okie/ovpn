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
