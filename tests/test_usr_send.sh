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
	cat > $userdir/tst_send1.ovpn <<CONF
client
auth-user-pass
<key>
-----BEGIN ENCRYPTED PRIVATE KEY-----
FAKE KEY
-----END ENCRYPTED PRIVATE KEY-----
</key>
CONF
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

function extractMailBody() {
	awk '
		/Content-Type: text\/plain; charset=utf-8/ { text=1; next }
		text && /Content-Transfer-Encoding: base64/ { body=1; next }
		body && /^--ovpnPart/ { exit }
		body { print }
	' "$1" | base64 -d
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
function deploySendMail() {
	deploySend
	sed -i '/nextcloudUrl/d' $ovpn/_config
	cat >> $ovpn/_config <<CFG
mailSmtpUrl=smtps://smtp.cloud.test:465
mailUser=smtpuser
mailPassword=smtppass
mailFrom=vpn@test.local
CFG
	#маршруты заново: первый матч в заглушке выигрывает, а базовый - без Email
	: > $CURL_ROUTES
	curlRoute "users/search?login=send1" '{"id":5,"Login":"send1","Email":"send1@test.local","Mobile":"+79001234567"}'
}

echo "доставка почтой (нет nextcloudUrl):"
deploySendMail
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "отправка через заданный SMTP" $CURL_LOG "smtps://smtp.cloud.test:465"
assertFileContains "авторизация на SMTP" $CURL_LOG "--user smtpuser:smtppass"
assertFileContains "получатель из инвентори" $CURL_LOG "--mail-rcpt send1@test.local"
mimefile=$(ls $CURL_UPLOADS/upload.* | tail -1)
assertFileContains "тема закодирована" $mimefile "Subject: =?UTF-8?B?"
assertFileContains "вложение с конфигом" $mimefile 'filename="tst_send1.ovpn"'
confBase64=$(base64 "$userdir/tst_send1.ovpn" | head -n1)
assertFileContains "содержимое конфига в base64" $mimefile "$confBase64"
assertFileContains "СМС с паролем по-прежнему уходит" $CURL_LOG "text=пароль на openvpn SECRETPASS"
mailbody=$(extractMailBody "$mimefile")
assertContains "письмо сообщает о пароле ключа" "Для подключения потребуется пароль приватного ключа." "$mailbody"
assertContains "письмо анонсирует СМС с паролем" "Пароль приватного ключа придёт отдельным СМС-сообщением." "$mailbody"
assertContains "письмо сообщает о 2FA" "Для подключения потребуется код двухфакторной аутентификации." "$mailbody"
assertContains "письмо анонсирует СМС с 2FA" "Секрет двухфакторной аутентификации придёт отдельным СМС-сообщением." "$mailbody"

echo "почта: требования определяются по вложенному конфигу, не по файлам секретов:"
deploySendMail
printf 'client\n' > $userdir/tst_send1.ovpn
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
mimefile=$(ls $CURL_UPLOADS/upload.* | tail -1)
mailbody=$(extractMailBody "$mimefile")
assertNotContains "письмо не обещает пароль без зашифрованного ключа" "СМС-сообщением" "$mailbody"
assertNotContains "пароль не отправлен для незашифрованного конфига" $CURL_LOG "text=пароль"
assertNotContains "2FA-секрет не отправлен без auth-user-pass" $CURL_LOG "text=Ключ Google"
assertFileNotContains "номер не запрашивается, когда СМС не нужны" $CURL_LOG "expand=private_phone"

echo "прямой e-mail вторым аргументом:"
deploySendMail
runSend send1 direct@example.com
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "письмо на указанный адрес" $CURL_LOG "--mail-rcpt direct@example.com"

echo "smtp:// с авторизацией - принудительный STARTTLS:"
deploySendMail
sed -i 's|mailSmtpUrl=.*|mailSmtpUrl=smtp://smtp.cloud.test:587|' $ovpn/_config
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "включен --ssl-reqd" $CURL_LOG "ssl-reqd"

echo "у пользователя нет e-mail:"
deploySendMail
: > $CURL_ROUTES
curlRoute "users/search?login=send1" '{"id":5,"Login":"send1"}'
runSend send1
assertExitCode "выход с кодом 31" "31" "$rc"

echo "оба транспорта заданы - приоритет за Nextcloud:"
deploySend
cat >> $ovpn/_config <<CFG
mailSmtpUrl=smtps://smtp.cloud.test:465
mailFrom=vpn@test.local
CFG
runSend send1
assertExitCode "успешное завершение" "0" "$rc"
assertFileContains "выгрузка в Nextcloud была" $CURL_LOG "MKCOL"
assertFileNotContains "почта не использовалась" $CURL_LOG "mail-rcpt"

summarize
