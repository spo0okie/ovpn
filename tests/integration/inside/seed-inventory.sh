#!/bin/bash
#выполняется В КОНТЕЙНЕРЕ server: ждет готовности API инвентори
#и сидирует тестовые данные через REST
set -e

#index.php в пути обязателен: без него запросы уходят на главную страницу
api=http://arms-app:8088/index.php/api

echo "жду API инвентори (миграции на пустой БД - небыстро)"
#поиск несуществующей записи отвечает 404 с JSON-телом - это тоже "готов";
#критерий готовности: ответ вообще парсится как JSON
ready=0
for i in $(seq 1 180); do
	if curl -s "$api/net-ips/search?name=probe" | jq -e . >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 2
done
if [ "$ready" != "1" ]; then
	echo "FAIL: API инвентори не поднялся (нет JSON-ответа за 6 минут)"
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
	usr=$(curl -s -d "Login=$u&Ename=Test $u&Persg=1&Uvolen=0&Email=$u@test.local" -X POST $api/users/create)
	if ! echo "$usr" | jq -e '.id != null' >/dev/null 2>&1; then
		echo "FAIL: пользователь $u не создан: $usr"
		exit 1
	fi
done

echo "SEED OK"
