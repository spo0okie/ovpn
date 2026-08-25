#!/bin/bash
#тесты usr.send: доставка конфигов через Nextcloud + СМС (через заглушку curl)
cd "$(dirname "$0")"
. ./helpers.sh

function deploySend() {
	newSandbox
	ovpn=$sandbox/ovpn
	mkdir -p $ovpn
	cp $REPO_DIR/usr.send $REPO_DIR/_lib $ovpn/
	cat > $ovpn/_config <<CFG
prefix=tst
ovpndir=$ovpn
nextcloudUrl=https://cloud.test.local
adUser=vpnbot
adPassword=secret
nextCloudUID=UID
smsApiUrl=https://sms.test.local/sms/send
inventoryApiUrl=https://inventory.test.local/api
CFG
	userdir=$ovpn/clients/tst-send1
	mkdir -p $userdir
	echo "FAKE CONF" > $userdir/tst_send1.ovpn
	echo "SECRETPASS" > $userdir/passwd.txt
	echo "GOOGLEKEY16CHARS" > $userdir/google.txt

	curlRoute "users/search?login=send1" '{"id":5,"Login":"send1","Mobile":"+79001234567"}'
	curlRoute "sharees?format=json" '{"ocs":{"data":{"exact":{"users":[{"label":"Send One (send1)","value":{"shareWith":"UUID-1"},"shareWithDisplayNameUnique":"s@x"}]},"users":[]}}}'
	curlRoute "dav/files/UID/openvpn/send1" '<d:href>/remote.php/dav/files/UID/openvpn/send1/tst_send1.ovpn</d:href>'
}

function runSend() {
	( cd $ovpn && ./usr.send "$@" ) > $sandbox/out.log 2>&1
	rc=$?
}

echo "полный цикл доставки:"
deploySend
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "конфиг загружен в Nextcloud" $CURL_LOG "openvpn/send1/tst_send1.ovpn"
assertFileContains "шара выдана найденному пользователю" $CURL_LOG "shareWith=UUID-1"
assertFileContains "СМС с паролем отправлена" $CURL_LOG "text=пароль на openvpn SECRETPASS"
assertFileContains "СМС с ключом 2FA отправлена" $CURL_LOG "text=Ключ Google GOOGLEKEY16CHARS"
assertFileContains "телефон нормализован" $CURL_LOG "sms/send/89001234567"

echo "без 2FA (нет google.txt) - ключ не отправляется:"
deploySend
rm $userdir/google.txt
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileNotContains "СМС с ключом не отправлялась" $CURL_LOG "text=Ключ Google"

echo "без пароля (нет passwd.txt) - СМС пароля не отправляется:"
deploySend
rm $userdir/passwd.txt
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileNotContains "СМС с паролем не отправлялась" $CURL_LOG "text=пароль"
assertFileContains "ключ 2FA все равно отправлен" $CURL_LOG "text=Ключ Google"

echo "без smsApiUrl - только шара, без СМС:"
deploySend
sed -i '/smsApiUrl/d' $ovpn/_config
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "шара выдана" $CURL_LOG "shareWith=UUID-1"
assertFileNotContains "СМС не отправлялись" $CURL_LOG "sms/send"

echo "модуль не настроен (нет nextcloudUrl):"
deploySend
sed -i '/nextcloudUrl/d' $ovpn/_config
runSend send1
assertExitCode "выход с кодом 1" "1" "$rc"
assertFileNotContains "никаких запросов не делалось" $CURL_LOG "openvpn/send1"

echo "нет ни одного конфига:"
deploySend
rm $userdir/tst_send1.ovpn
runSend send1
assertExitCode "выход с кодом 11" "11" "$rc"
summarize
