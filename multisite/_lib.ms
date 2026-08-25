#!/bin/bash
#мультисайт-специфичные функции: дополняют корневую _lib
#(подключать после нее: . $SCRIPTPATH/_lib; . $SCRIPTPATH/_lib.ms)

#конвертировать имя конфига в логин пользователя
#contoso-ais-pupkin.v-notebook -> ais-pupkin
function getConfigUser() {
	configDir=`getConfigDir $1`
	configUsernameFile=$configDir/username.txt
	if [ -s $configUsernameFile ]; then
		cat $configUsernameFile
	else
		user=`echo $1|cut -d- -f1`
		#если имя не содержит точки, то предполагаем что это префикс
		if [[ $user == *"."* ]]; then
			echo $user
		else
			echo $1|cut -d- -f1-2
		fi
	fi
}

#конвертирует IP адрес из сети 2FAopenvpn в сеть openvpn того же филиала
#$1 - IP
#$2 - сайт
function 2faToNormalIp() {
	addr=$1
	site=$2

	#формируем переменную mhk__openvpn2fa_lan
	site_ovpn2fa_lan_var=${site}_openvpn2fa_lan
	#получаем значение
	site_ovpn2fa_lan=${!site_ovpn2fa_lan_var}
	#если такая переменная есть (а не везде для 2FA отдельные сети), то подменяем префиксы IP
	if [ -n "$site_ovpn2fa_lan" ]; then
		site_ovpn_lan_var=${site}_openvpn_lan
		site_ovpn_lan=${!site_ovpn_lan_var}

		site_subnet=`echo $site_ovpn_lan | cut -d'.' -f1-3`
		site_2fasubnet=`echo $site_ovpn2fa_lan | cut -d'.' -f1-3`

		echo $addr |sed "s/^$site_2fasubnet/$site_subnet/"
	else
		echo $addr
	fi
}

#конвертирует IP адрес из сети openvpn в сеть 2FAopenvpn того же филиала
#$1 - IP
#$2 - сайт
function normalTo2faIp() {
	addr=$1
	site=$2

	#формируем переменную mhk__openvpn2fa_lan
	site_ovpn2fa_lan_var=${site}_openvpn2fa_lan
	#получаем значение
	site_ovpn2fa_lan=${!site_ovpn2fa_lan_var}
	#если такая переменная есть (а не везде для 2FA отдельные сети), то подменяем префиксы IP
	if [ -n "$site_ovpn2fa_lan" ]; then
		site_ovpn_lan_var=${site}_openvpn_lan
		site_ovpn_lan=${!site_ovpn_lan_var}

		site_subnet=`echo $site_ovpn_lan | cut -d'.' -f1-3`
		site_2fasubnet=`echo $site_ovpn2fa_lan | cut -d'.' -f1-3`

		echo $addr |sed "s/^$site_subnet/$site_2fasubnet/"
	else
		echo $addr
	fi
}
