#!/bin/bash
#выполняется В КОНТЕЙНЕРЕ client: подключается конфигом $1 к серверу
# $1 - путь к .ovpn конфигу
# $2 - ожидание: success | fail
# $3 - (опционально) подстрока, которую ищем в логе клиента
#      (например пушнутый маршрут)

config=$1
expect=$2
wantline=$3
askpass=$4	#файл с паролем ключа (для usePassKey-конфигов)
log=/tmp/client.log
timeout=${CONNECT_TIMEOUT:-30}

rm -f $log
pkill -f "openvpn --config" 2>/dev/null
sleep 1

extra=""
[ -n "$askpass" ] && extra="--askpass $askpass"
openvpn --config "$config" --log "$log" --verb 3 --connect-retry-max 3 $extra &
pid=$!

up=0
for i in $(seq 1 $timeout); do
	if grep -q "Initialization Sequence Completed" $log 2>/dev/null; then
		up=1
		break
	fi
	kill -0 $pid 2>/dev/null || break
	sleep 1
done

rc=0
if [ "$expect" == "success" ]; then
	if [ $up -ne 1 ]; then
		echo "FAIL: туннель не поднялся ($config)"
		tail -15 $log
		rc=1
	elif ! ping -c 2 -W 3 192.168.77.1 >/dev/null; then
		echo "FAIL: туннель поднялся, но сервер не пингуется"
		rc=1
	elif [ -n "$wantline" ] && ! { ip route | grep -qF -- "$wantline" || grep -qF -- "$wantline" $log; }; then
		echo "FAIL: маршрут '$wantline' не появился ни в таблице, ни в логе"
		ip route | tail -5
		rc=1
	else
		echo "CONNECT OK"
	fi
else
	if [ $up -eq 1 ]; then
		echo "FAIL: туннель поднялся, хотя не должен был ($config)"
		rc=1
	else
		echo "REJECT OK"
	fi
fi

kill $pid 2>/dev/null
wait $pid 2>/dev/null
exit $rc
