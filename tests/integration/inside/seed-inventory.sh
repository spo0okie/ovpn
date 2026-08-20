#!/bin/bash
#выполняется В КОНТЕЙНЕРЕ server: ждет готовности API инвентори
#и сидирует тестовые данные через REST
set -e

api=http://arms-app:8088/web/api

echo "жду API инвентори (миграции на пустой БД - небыстро)"
code=000
for i in $(seq 1 180); do
	code=$(curl -s -o /dev/null -w '%{http_code}' "$api/net-ips/search?name=probe" || true)
	[ "$code" == "200" ] && break
	sleep 2
done
if [ "$code" != "200" ]; then
	echo "FAIL: API инвентори не поднялся (последний http-код: $code)"
	exit 1
fi

echo "сидирую тестовую сеть"
net=$(curl -s -d "text_addr=192.168.77.0/24&name=ovpn-test-net" -X POST $api/networks/create)
if ! echo "$net" | jq -e '.id != null' >/dev/null 2>&1; then
	echo "FAIL: сеть не создана: $net"
	exit 1
fi

#адрес сервера туннеля помечаем занятым, чтобы first-unused не выдал его клиенту
curl -s -d "text_addr=192.168.77.1&name=ovpn-server-gw" -X POST $api/net-ips/create >/dev/null

#пользователи с Login = имени конфига (usr.new привязывает IP по этому логину)
for u in inv1 inv2; do
	usr=$(curl -s -d "Login=$u&Ename=Test $u&Persg=1&Uvolen=0" -X POST $api/users/create)
	if ! echo "$usr" | jq -e '.id != null' >/dev/null 2>&1; then
		echo "FAIL: пользователь $u не создан: $usr"
		exit 1
	fi
done

echo "SEED OK"
