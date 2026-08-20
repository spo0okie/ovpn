#!/bin/bash
for f in certs/revoked/*.pem; do
	name=`openssl x509 -in $f -noout -text | grep 'Subject: C = ' | cut -d',' -f6 | cut -d'=' -f2 | tr -d ' ='`
	if [ -z "$1" ]; then
		echo "$name	$f"
	elif [ "$name" = "$1" ]; then
		echo $f
		exit 0
	fi
done