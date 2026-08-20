#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )" #"
. $SCRIPTPATH/_config

if [ -n "$1" ]; then
	f="./clients/$prefix-$1/${prefix}_$1.crt"
	#echo searchin $f
	if [ -e $f ]; then
		echo $f
		exit 0
	fi
fi

for f in certs/*.pem; do
	name=`openssl x509 -in $f -noout -text | grep 'Subject: C = ' | cut -d',' -f6 | cut -d'=' -f2 | tr -d ' ='`
	if [ -z "$1" ]; then
		echo "$name	$f"
	elif [ "$name" = "$1" ]; then
		echo $f
		exit 0
	fi
done

