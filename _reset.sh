#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )" #"
. $SCRIPTPATH/_config
. $SCRIPTPATH/_lib

#сеть в формате "адрес маска": 10.0.0.0/24 -> "10.0.0.0 255.255.255.0"
#адрес без суффикса получает маску /24 (историческое поведение)
function netAndMask() {
	m=`suffix2mask $1`
	if [ "$m" == "$1" ]; then
		echo "$1 255.255.255.0"
	else
		echo "$m"
	fi
}

#путь к PAM-плагину google-authenticator (2FA-инстансы)
pamPlugin=${pamPlugin:-/usr/lib/x86_64-linux-gnu/openvpn/plugin/openvpn-plugin-auth-pam.so}

#генерация server-конфига инстанса $2 ($1 - путь к конфигу).
#атрибуты берутся через inst_var: в вырожденном случае (instances не задан)
#это legacy-переменные и файл server.conf; при instances - server-<instance>.conf.
function writeServerConf() {
	conf=$1
	inst=$2

	srvlan=$(inst_var $inst lan)
	srvport=$(inst_var $inst port)
	srvproto=$(inst_var $inst proto)
	srvdns=$(inst_var $inst dns)
	srvroutes=$(inst_var $inst routes)
	srvccddir=$(inst_var $inst ccd_dir)
	tag=$(instFileSuffix - "$inst")

	echo "dev tun" > $conf
	echo "port $srvport" >> $conf
	echo "proto $srvproto" >> $conf
	echo "ca $ovpndir/ca.pem" >> $conf
	echo "cert $ovpndir/$prefix-serv.cert" >> $conf
	echo "key $ovpndir/$prefix-serv.key" >> $conf
	echo "tls-auth $ovpndir/ta.key" >> $conf
	echo "dh $ovpndir/dh1024.pem" >> $conf
	echo "crl-verify $ovpndir/clients/revoked.crl" >> $conf
	echo "tls-server" >> $conf
	echo "cipher AES-256-CBC" >> $conf
	echo "data-ciphers AES-256-CBC" >> $conf
	echo "server `netAndMask $srvlan`" >> $conf
	echo "topology subnet" >> $conf
	echo "persist-key" >> $conf
	echo "persist-tun" >> $conf
	echo "fast-io" >> $conf
	#echo "comp-lzo" >> $conf
	echo "status /var/log/openvpn$tag.status" >> $conf
	echo "ifconfig-pool-persist $ovpndir/pool$tag.ip 360000" >> $conf
	echo "log-append /var/log/openvpn$tag-server.log" >> $conf
	echo "client-config-dir $srvccddir" >> $conf
	echo "client-connect $ovpndir/route-client" >> $conf
	echo "verb 3" >> $conf
	echo "mute 10" >> $conf
	echo "script-security 2" >> $conf
	echo ";link-mtu 1472" >> $conf
	echo "keepalive 10 60" >> $conf

	if [ -n "$instances" ]; then
		#каждый инстанс в multi-instance - собственный server_name для logserver
		echo "setenv OPENVPN_SERVER_NAME $inst" >> $conf
		if [ "$(inst_var $inst auth_mode)" = "2fa" ]; then
			echo "plugin $pamPlugin openvpn" >> $conf
		fi
	fi

	echo "push \"route `netAndMask $srvlan`\"" >> $conf

	for netw in $srvroutes; do
	    echo "push \"route `netAndMask $netw`\"" >> $conf
	done

	for ns in $srvdns; do
	    echo "push \"dhcp-option DNS $ns\"" >> $conf
	done
}


echo "WARINNG NOW RESETING OPENVPN SERVER CERTIFICATES ($org/$prefix $srvname/$srvaddr)"
echo "Press Ctrl+C to abort..."
waittime="9 8 7 6 5 4 3 2 1 0 Last_Chance !!!!!!!"
#waittime="NOREMORSE"
for t in $waittime; do
    echo $t
    sleep 2
done

#echo "Comment that line to really reset server ..." && exit

echo "Clearing data ... "
rm -f ./*.pem
rm -f ./certs/*.pem
rm -f ./*.key
rm -f ./*.key
rm -f ./*.cert
rm -f ./*.csr
rm -rf ./clients
mkdir ./clients
mkdir ./clients/revoked
touch ./clients/revoked.crl

echo "Zeroing counters"
rm -f ./*.old
> ./clients/index
echo "00" > ./clients/serial
echo "00" > ./clients/crlnumber


mkdir -p ./certs
mkdir -p ./ccd

echo "Creating sertificates ... "
echo -e "RU\nUral\nChel\n$org\nIT\n$srvname\n\n" | openssl req -config $sslconf -new -nodes -x509 -keyout ca.key -out ca.pem -days 3650 -sha256

openssl genrsa -out $prefix-serv.key
chmod 400 ./$prefix-serv.key
echo -e "RU\nUral\nChel\n$org\nIT\n$srvname\n\n\n" | openssl req -config $sslconf -new -nodes -key $prefix-serv.key -out $prefix-serv.csr
openssl ca -config $sslconf -batch -in $prefix-serv.csr -out $prefix-serv.cert
openvpn --genkey --secret ta.key
openssl dhparam -out dh1024.pem 4096

echo "Generating config ... "

#в вырожденном случае getInstances вернёт один "local" -> server.conf
for inst in $(getInstances); do
	writeServerConf ./server$(instFileSuffix - "$inst").conf "$inst"
done

echo "Initializing revoke.crl"
./usr.new revoke_me
./usr.revoke revoke_me

if [ ! -f ./route-client ]; then
    echo -e "#!/bin/sh\nexit 0" > ./route-client
fi

if [ ! -x ./route-client ]; then
    chmod 555 ./route-client
fi


echo "done"
