#!/bin/bash
#тесты функций базовой _lib
cd "$(dirname "$0")"
. ./helpers.sh

. $REPO_DIR/_lib

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

echo "inventoryGetPinnedIp/inventoryGetUnusedIp (через заглушку curl):"
newSandbox
export inventoryApiUrl=https://inventory.test.local/api
export vpnnet=10.64.68.0/24

curlRoute "net-ips/search?name=ovpn-testuser" '{"id":7,"text_addr":"10.64.68.5","name":"ovpn-testuser"}'
curlRoute "net-ips/first-unused" '{"text_addr":"10.64.68.9"}'

assertEquals "pinned IP найден" "10.64.68.5" "`inventoryGetPinnedIp ovpn-testuser`"
assertEquals "pinned IP не найден -> null" "null" "`inventoryGetPinnedIp ovpn-nonexistent`"
assertEquals "первый свободный IP с маской" "10.64.68.9 255.255.255.0" "`inventoryGetUnusedIp $vpnnet`"

#свободных адресов нет -> exit 10
newSandbox
curlRoute "net-ips/first-unused" '{"text_addr":null}'
out=`inventoryGetUnusedIp $vpnnet 2>/dev/null`
assertExitCode "нет свободных IP" "10" "$?"

summarize
