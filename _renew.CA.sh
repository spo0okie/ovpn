#!/bin/bash

openssl x509 -in ca.pem -days 3650 -out ca-new.pem -signkey ca.key -sha256