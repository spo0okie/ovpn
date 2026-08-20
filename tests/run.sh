#!/bin/bash
#запуск всех тестов: bash tests/run.sh
#зависимости: bash, jq, coreutils. curl/google-authenticator подменяются заглушками
cd "$(dirname "$0")"

echo "== проверка синтаксиса скриптов"
synfail=0
for f in ../_lib ../_lib.inv ../_reset.sh ../_renew.CA.sh ../upd.crl ../usr.* \
         ../multisite/_lib ../multisite/_ccd.check ../multisite/usr.*; do
	if ! bash -n "$f" 2>&1; then
		echo "  SYNTAX FAIL: $f"
		synfail=1
	fi
done
[ $synfail -eq 0 ] && echo "  ok"

totalFiles=0
failedFiles=0
for t in test_*.sh; do
	echo "== $t"
	bash "$t" || failedFiles=$((failedFiles+1))
	totalFiles=$((totalFiles+1))
done

echo
if [ $synfail -gt 0 ] || [ $failedFiles -gt 0 ]; then
	echo "ПРОВАЛ: $failedFiles из $totalFiles файлов тестов"
	exit 1
fi
echo "OK: все тесты пройдены ($totalFiles файлов)"
