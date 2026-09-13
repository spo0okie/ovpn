#!/bin/bash
#тесты ip2var: подстановка переменных вместо IP-адресов в скрипт с iptables
cd "$(dirname "$0")"
. ./helpers.sh

#файл переменных в том виде, в каком его генерирует usr.ccd2env
function deployVars() {
	newSandbox
	vars=$sandbox/ccd.env
	script=$sandbox/fw.sh
	cat > $vars <<'VARS'
#!/bin/bash
# Auto-generated VPN user IP assignments
# Generated on 2026-09-13T00:00:00Z

u10_local=10.32.0.5
u10_local_2fa=10.132.0.7
u11_local=10.32.0.50
VARS
	cat > $script <<'FW'
#!/bin/bash
iptables -A FORWARD -s 10.32.0.5 -j ACCEPT
iptables -A FORWARD -s 10.32.0.50 -d 10.132.0.7 -j ACCEPT
iptables -A FORWARD -s 10.32.0.5,10.132.0.7 -j ACCEPT
iptables -A FORWARD -s 10.32.0.5/32 -j ACCEPT
iptables -A FORWARD -s 10.32.0.99 -j ACCEPT
FW
}

echo "ip2var - подстановка в файл результата:"
deployVars
out=$sandbox/fw.vars.sh
bash $REPO_DIR/ip2var $vars $script $out > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "адрес заменен переменной" $out 'iptables -A FORWARD -s ${u10_local} -j ACCEPT'
assertFileContains "более длинный адрес не перепутан с коротким" $out '-s ${u11_local} -d ${u10_local_2fa}'
assertFileContains "адреса через запятую" $out '-s ${u10_local},${u10_local_2fa}'
assertFileContains "адрес с маской" $out '-s ${u10_local}/32'
assertFileContains "незнакомый адрес остался как есть" $out "10.32.0.99"
assertFileContains "шапка скрипта на месте" $out "#!/bin/bash"
assertFileContains "сводка подстановки" $sandbox/out.log "подставлено переменных: 3 из 3"
assertFileContains "исходный скрипт не изменен" $script "-s 10.32.0.5 -j ACCEPT"

echo "ip2var - вывод в stdout:"
deployVars
res=$(bash $REPO_DIR/ip2var $vars $script 2>/dev/null)
assertExitCode "успешное завершение" "0" "$?"
assertContains "stdout: адрес заменен" '-s ${u10_local} -j ACCEPT' "$res"
assertNotContains "stdout: исходного адреса нет" '-s 10.32.0.5 -j' "$res"

echo "ip2var - переменная без совпадений в скрипте:"
deployVars
cat > $script <<'FW'
#!/bin/bash
iptables -A FORWARD -s 10.32.0.5 -j ACCEPT
FW
bash $REPO_DIR/ip2var $vars $script $sandbox/fw.vars.sh > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "в сводке видно, что подставлена одна из трех" $sandbox/out.log "подставлено переменных: 1 из 3"

echo "ip2var - повторяющийся адрес:"
deployVars
printf 'u12_local=10.32.0.5\n' >> $vars
bash $REPO_DIR/ip2var $vars $script $sandbox/fw.vars.sh > $sandbox/out.log 2>&1
assertExitCode "успешное завершение" "0" "$?"
assertFileContains "предупреждение о дубле" $sandbox/out.log "адрес 10.32.0.5 повторяется"
assertFileContains "оставлена первая переменная" $sandbox/fw.vars.sh '${u10_local}'

echo "ip2var - ошибки в аргументах:"
deployVars
bash $REPO_DIR/ip2var > $sandbox/out.log 2>&1
assertExitCode "без аргументов - код 1" "1" "$?"
assertFileContains "подсказка по использованию" $sandbox/out.log "использование: ip2var"
bash $REPO_DIR/ip2var $vars $sandbox/nosuchfile > $sandbox/out.log 2>&1
assertExitCode "нет скрипта - код 1" "1" "$?"
bash $REPO_DIR/ip2var $sandbox/nosuchfile $script > $sandbox/out.log 2>&1
assertExitCode "нет файла переменных - код 1" "1" "$?"

echo "ip2var - в файле переменных нет адресов:"
deployVars
printf '#!/bin/bash\n# Auto-generated VPN user IP assignments\n' > $vars
bash $REPO_DIR/ip2var $vars $script > $sandbox/out.log 2>&1
assertExitCode "нечего подставлять - код 1" "1" "$?"
assertFileContains "понятное сообщение" $sandbox/out.log "нет ни одного адреса"

summarize
