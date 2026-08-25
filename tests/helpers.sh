#!/bin/bash
#общие функции тестов: sandbox, заглушки, assert'ы
#подключается из test_*.sh: . ./helpers.sh

TESTS_DIR="$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1; pwd -P )"
REPO_DIR="$( dirname "$TESTS_DIR" )"

checks=0
failures=0

function assertEquals() { #имя ожидание факт
	checks=$((checks+1))
	if [ "$2" = "$3" ]; then
		echo "  ok: $1"
	else
		echo "  FAIL: $1"
		echo "    ожидалось: $2"
		echo "    получено:  $3"
		failures=$((failures+1))
	fi
}

function assertExitCode() { #имя ожидание факт
	assertEquals "$1 (код выхода)" "$2" "$3"
}

function assertFileContains() { #имя файл подстрока
	checks=$((checks+1))
	if grep -qF -- "$3" "$2" 2>/dev/null; then
		echo "  ok: $1"
	else
		echo "  FAIL: $1"
		echo "    файл $2 не содержит: $3"
		failures=$((failures+1))
	fi
}

function assertFileNotContains() { #имя файл подстрока
	checks=$((checks+1))
	if grep -qF -- "$3" "$2" 2>/dev/null; then
		echo "  FAIL: $1"
		echo "    файл $2 содержит запрещенное: $3"
		failures=$((failures+1))
	else
		echo "  ok: $1"
	fi
}

function assertFileExists() { #имя файл
	checks=$((checks+1))
	if [ -s "$2" ]; then
		echo "  ok: $1"
	else
		echo "  FAIL: $1 (нет файла $2)"
		failures=$((failures+1))
	fi
}

function assertFileMissing() { #имя файл
	checks=$((checks+1))
	if [ -e "$2" ]; then
		echo "  FAIL: $1 (файл $2 не должен существовать)"
		failures=$((failures+1))
	else
		echo "  ok: $1"
	fi
}

#создает чистую песочницу с заглушками curl/google-authenticator в PATH
#результат в переменной $sandbox
function newSandbox() {
	sandbox=`mktemp -d`
	mkdir -p $sandbox/bin
	cp $TESTS_DIR/stubs/* $sandbox/bin/
	chmod +x $sandbox/bin/*
	export PATH=$sandbox/bin:$PATH
	export CURL_LOG=$sandbox/curl.log
	export CURL_UPLOADS=$sandbox/uploads
	export CURL_ROUTES=$sandbox/curl.routes
	export GAUTH_LOG=$sandbox/gauth.log
	: > $CURL_LOG
	: > $CURL_ROUTES
	: > $GAUTH_LOG
}

#добавить маршрут заглушке curl: подстрока_URL -> json-ответ
function curlRoute() { #подстрока json
	resp=`mktemp`
	echo "$2" > $resp
	printf '%s\t%s\n' "$1" "$resp" >> $CURL_ROUTES
}

#итог файла тестов: печатает сводку, выходит 1 при провалах
function summarize() {
	echo "  ($checks проверок, $failures провалов)"
	[ $failures -gt 0 ] && exit 1
	exit 0
}
