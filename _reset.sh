#!/bin/bash
. ./_config
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
conf=./server.conf

echo "dev tun" > $conf
echo "port $port" >> $conf
echo "proto $proto" >> $conf
echo "ca $ovpndir/ca.pem" >> $conf
echo "cert $ovpndir/$prefix-serv.cert" >> $conf
echo "key $ovpndir/$prefix-serv.key" >> $conf
echo "tls-auth $ovpndir/ta.key" >> $conf
echo "dh $ovpndir/dh1024.pem" >> $conf
echo "crl-verify $ovpndir/clients/revoked.crl" >> $conf
echo "tls-server" >> $conf
echo "cipher AES-256-CBC" >> $conf
echo "data-ciphers AES-256-CBC" >> $conf
echo "server $vpnnet 255.255.255.0" >> $conf
echo "topology subnet" >> $conf
echo "persist-key" >> $conf
echo "persist-tun" >> $conf
echo "fast-io" >> $conf
#echo "comp-lzo" >> $conf
echo "status /var/log/openvpn.status" >> $conf
echo "ifconfig-pool-persist $ovpndir/pool.ip 360000" >> $conf
echo "log-append /var/log/openvpn-server.log" >> $conf
echo "client-config-dir $ovpndir/ccd" >> $conf
echo "client-connect $ovpndir/route-client" >> $conf
echo "verb 3" >> $conf
echo "mute 10" >> $conf
echo "script-security 2" >> $conf
echo ";link-mtu 1472" >> $conf
echo "keepalive 10 60" >> $conf

echo "push \"route $vpnnet 255.255.255.0\"" >> $conf

for netw in $subnets; do
    echo "push \"route $netw 255.255.255.0\"" >> $conf
done

for ns in $dns; do
    echo "push \"dhcp-option DNS $ns\"" >> $conf
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