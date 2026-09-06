#!/bin/bash
# разовая миграция продовых данных multisite -> модель инстансов
#
# Запускать НА АДМИН-ХОСТЕ до перехода на новые скрипты. В _config должны
# оставаться старые переменные (sites, <site>_openvpn_lan / _openvpn2fa_lan)
# для разбора подсетей; новые (instances, <instance>_inv_prefix, <instance>_auth_mode)
# - для переименования IP-записей инвентори.
#
# Делает:
#  1. переименование CCD: ccd.<site> -> ccd.<site>      (обычный инстанс)
#                                   -> ccd.<site>-2fa   (2FA-инстанс)
#     (аналогично ccd.<site>.disabled -> ccd.<site>-2fa.disabled)
#  2. переименование IP-записей инвентори, только если <instance>_inv_prefix
#     отличен от дефолта (ovpn- для normal, ovpn2fa- для 2fa).
#
# Режим (обычный/2FA) определяется по подсети из ifconfig-push - старая подсетная
# логика multisite (работает только для /24). Скрипт идемпотентен.

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )" #"
. $SCRIPTPATH/_config
. $SCRIPTPATH/_lib.inv

if [ -z "$sites" ]; then
	echo "нет sites в _config - похоже, это не multisite-конфигурация"
	exit 1
fi

clientsDir=${clientsDir:-$ovpndir/clients}
[ -d "$clientsDir" ] || { echo "нет каталога клиентов $clientsDir"; exit 1; }

# режим CCD по подсети (копия старой подсетной логики multisite; только /24)
function ccdMode() { # $1=ccd файл  $2=site
	local network=`grep -vE '^#' "$1" | grep 'ifconfig-push' | head -n 1 | cut -d' ' -f2`
	if [ -z "$network" ]; then
		echo "NONE"
		return 0
	fi
	local subnet=`echo $network | cut -d'.' -f1-3`
	local site_lan_var=${2}_openvpn_lan
	local site_lan=${!site_lan_var}
	local site_subnet=`echo $site_lan | cut -d'.' -f1-3`
	if [ "$site_subnet" = "$subnet" ]; then
		echo "OVPN"
		return 0
	fi
	local site_2fa_var=${2}_openvpn2fa_lan
	local site_2fa=${!site_2fa_var}
	if [ -n "$site_2fa" ]; then
		local site_2fasubnet=`echo $site_2fa | cut -d'.' -f1-3`
		if [ "$site_2fasubnet" = "$subnet" ]; then
			echo "OVPN2FA"
			return 0
		fi
	fi
	echo "UNKNOWN"
}

renamed=0
for d in "$clientsDir"/$prefix-*; do
	[ -d "$d" ] || continue
	for site in $sites; do
		for f in "$d/ccd.$site" "$d/ccd.$site.disabled"; do
			[ -e "$f" ] || continue
			mode=`ccdMode "$f" $site`
			case "$mode" in
				OVPN)
					# обычный инстанс = имя сайта: ccd.<site> уже корректно
					;;
				OVPN2FA)
					base=${f##*/}
					newbase=${base/ccd.$site/ccd.$site-2fa}
					target="$d/$newbase"
					if [ -e "$target" ]; then
						echo "уже есть $target - пропускаю $f"
					else
						mv "$f" "$target"
						echo "переименован $f -> $target"
						renamed=$((renamed+1))
					fi
					;;
				*)
					echo "WARN: $f - не удалось определить режим ($mode), не трогаю"
					;;
			esac
		done
	done
done
echo "переименовано CCD: $renamed"

# === переименование IP-записей инвентори (опционально) ===
if [ -n "$instances" ] && [ -n "$inventoryApiUrl" ]; then
	for d in "$clientsDir"/$prefix-*; do
		[ -d "$d" ] || continue
		user=${d##*/$prefix-}
		for inst in $instances; do
			san=$(echo "$inst" | tr '-' '_')
			auth_var=${san}_auth_mode
			auth=${!auth_var}
			prefix_var=${san}_inv_prefix
			newprefix=${!prefix_var}
			if [ -z "$newprefix" ]; then
				[ "$auth" = "2fa" ] && newprefix="ovpn2fa-" || newprefix="ovpn-"
			fi
			ccd="$d/ccd.$inst"
			[ -e "$ccd" ] || continue
			ip=`grep -vE '^#' "$ccd" | grep 'ifconfig-push' | head -n 1 | cut -d' ' -f2`
			[ -z "$ip" ] && continue
			# имя уже корректное - пропускаем; иначе переименовываем запись по адресу
			if [ -n "$newprefix" ] && [ "$newprefix" != "ovpn-" ] && [ "$auth" != "2fa" ]; then
				inventorySetIpInfo $ip ${newprefix}${user} >/dev/null
				echo "инвентори: $ip -> ${newprefix}${user}"
			elif [ -n "$newprefix" ] && [ "$newprefix" != "ovpn2fa-" ] && [ "$auth" = "2fa" ]; then
				inventorySetIpInfo $ip ${newprefix}${user} >/dev/null
				echo "инвентори: $ip -> ${newprefix}${user}"
			fi
		done
	done
else
	echo "инвентори: переименование пропущено (нет instances/inventoryApiUrl в _config)"
fi

echo "Готово. Дальше: обновить _config (убрать sites, оставить instances) и скрипты."
