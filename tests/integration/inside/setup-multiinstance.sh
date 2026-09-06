#!/bin/bash
#выполняется В КОНТЕЙНЕРЕ server2: раскладка скриптов, инициализация ДВУХ
#инстансов (обычный + 2FA) на одном хосте через _reset.sh с instances
set -e

ovpn=/etc/openvpn

cp /repo/usr.new /repo/usr.gen.ccd /repo/usr.send /repo/usr.enable /repo/usr.disable \
   /repo/usr.revoke /repo/usr.show /repo/usr.publish /repo/_lib /repo/_lib.inv \
   /repo/_reset.sh /repo/_renew.CA.sh /repo/upd.crl /repo/openssl.cnf $ovpn/
chmod 755 $ovpn/usr.* $ovpn/_reset.sh $ovpn/_renew.CA.sh $ovpn/upd.crl

cat > $ovpn/_config <<'CFG'
org=TestOrg
prefix=tst
srvname=tst-server
srvaddr=server2
proto=udp
port=1194
vpnnet=192.168.88.0/24
subnets="172.30.0.0/16"
dns="192.168.88.1"
ovpndir=/etc/openvpn
sslconf=$ovpndir/openssl.cnf
inventoryApiUrl=
instances="local local-2fa"
local_addr=server2
local_port=1194
local_proto=udp
local_lan=192.168.88.0/24
local_routes="172.30.0.0/16"
local_dns="192.168.88.1"
local_auth_mode=normal
local_ccd_dir=/etc/openvpn/ccd
local_delivery=local
local_inv_prefix="ovpn-"
local_2fa_addr=server2
local_2fa_port=1196
local_2fa_proto=udp
local_2fa_lan=192.168.188.0/24
local_2fa_routes="172.30.0.0/16"
local_2fa_dns="192.168.188.1"
local_2fa_auth_mode=2fa
local_2fa_ccd_dir=/etc/openvpn/ccd-2fa
local_2fa_delivery=local
local_2fa_inv_prefix="ovpn2fa-"
local_2fa_gauth_dir=/etc/google-auth
CFG

cd $ovpn

#убираем паузы обратного отсчета (в тестах некому жать Ctrl+C)
sed -i 's/^\(\s*\)sleep 2$/\1:/' _reset.sh usr.revoke

echo "=== _reset.sh (multi-instance) ==="
./_reset.sh

echo "=== проверка результатов инициализации ==="
for f in ca.pem ca.key tst-serv.cert tst-serv.key ta.key dh1024.pem \
         server-local.conf server-local-2fa.conf clients/revoked.crl route-client; do
	if [ ! -e "$f" ]; then
		echo "FAIL: после _reset.sh нет файла $f"
		exit 1
	fi
done

if ! grep -q "^server 192.168.88.0 255.255.255.0$" server-local.conf; then
	echo "FAIL: server-local.conf: нет корректной строки server"
	exit 1
fi
if ! grep -q "^server 192.168.188.0 255.255.255.0$" server-local-2fa.conf; then
	echo "FAIL: server-local-2fa.conf: нет корректной строки server (2FA-подсеть)"
	exit 1
fi
if ! grep -q "^port 1196$" server-local-2fa.conf; then
	echo "FAIL: server-local-2fa.conf: нет порта 2FA"
	exit 1
fi
if ! grep -qF 'client-config-dir /etc/openvpn/ccd-2fa' server-local-2fa.conf; then
	echo "FAIL: server-local-2fa.conf: нет отдельного client-config-dir"
	exit 1
fi
if ! grep -qF 'plugin' server-local-2fa.conf | grep -q 'openvpn-plugin-auth-pam.so'; then
	echo "FAIL: server-local-2fa.conf: нет PAM-плагина"
	exit 1
fi
if ! grep -qF 'setenv OPENVPN_SERVER_NAME local-2fa' server-local-2fa.conf; then
	echo "FAIL: server-local-2fa.conf: нет setenv OPENVPN_SERVER_NAME"
	exit 1
fi

echo "=== запуск обычного инстанса (2FA-инстанс не стартуем: нет PAM-сервиса) ==="
openvpn --config server-local.conf --daemon
for i in $(seq 1 15); do
	grep -q "Initialization Sequence Completed" /var/log/openvpn-local-server.log 2>/dev/null && break
	sleep 1
done
if ! grep -q "Initialization Sequence Completed" /var/log/openvpn-local-server.log; then
	echo "FAIL: openvpn-сервер (local) не поднялся"
	tail -20 /var/log/openvpn-local-server.log
	exit 1
fi

echo "SETUP OK"
