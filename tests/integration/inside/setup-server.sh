#!/bin/bash
#выполняется В КОНТЕЙНЕРЕ server: разворачивает скрипты в /etc/openvpn,
#инициализирует инстанс (_reset.sh) и запускает openvpn-сервер
set -e

ovpn=/etc/openvpn

cp /repo/usr.new /repo/usr.gen.ccd /repo/usr.send /repo/usr.enable /repo/usr.disable /repo/usr.revoke \
   /repo/usr.show /repo/usr.publish /repo/_lib /repo/_lib.inv /repo/_reset.sh /repo/_renew.CA.sh \
   /repo/upd.crl /repo/openssl.cnf $ovpn/
chmod 755 $ovpn/usr.* $ovpn/_reset.sh $ovpn/_renew.CA.sh $ovpn/upd.crl

cat > $ovpn/_config <<'CFG'
org=TestOrg
prefix=tst
srvname=tst-server
srvaddr=server
proto=udp
port=1194
vpnnet=192.168.77.0/24
subnets="172.20.0.0/16"
dns="192.168.77.1"
ovpndir=/etc/openvpn
sslconf=$ovpndir/openssl.cnf
inventoryApiUrl=
CFG

cd $ovpn

#убираем паузы обратного отсчета (в тестах некому жать Ctrl+C)
sed -i 's/^\(\s*\)sleep 2$/\1:/' _reset.sh usr.revoke

echo "=== _reset.sh (dhparam 4096 - это долго) ==="
./_reset.sh

echo "=== проверка результатов инициализации ==="
for f in ca.pem ca.key tst-serv.cert tst-serv.key ta.key dh1024.pem \
         server.conf clients/serial clients/index clients/revoked.crl \
         route-client; do
	if [ ! -e "$f" ]; then
		echo "FAIL: после _reset.sh нет файла $f"
		exit 1
	fi
done

if ! grep -q "^server 192.168.77.0 255.255.255.0$" server.conf; then
	echo "FAIL: server.conf: нет корректной строки server"
	grep "^server" server.conf
	exit 1
fi
if ! grep -qF 'push "route 172.20.0.0 255.255.0.0"' server.conf; then
	echo "FAIL: server.conf: нет пуша маршрута подсети"
	exit 1
fi

echo "=== запуск openvpn-сервера ==="
openvpn --config server.conf --daemon
for i in $(seq 1 15); do
	grep -q "Initialization Sequence Completed" /var/log/openvpn-server.log 2>/dev/null && break
	sleep 1
done
if ! grep -q "Initialization Sequence Completed" /var/log/openvpn-server.log; then
	echo "FAIL: openvpn-сервер не поднялся"
	tail -20 /var/log/openvpn-server.log
	exit 1
fi

echo "SETUP OK"
