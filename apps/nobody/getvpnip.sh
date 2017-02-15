#!/bin/bash

# define websites to connect to in order to get external ip address
pri_external_ip_website="https://ipinfo.io/"
sec_external_ip_website="https://jsonip.com/"

# create function to get the external ip address for tunnel
get_external_ip() {

	# required to force return code from function
	set -e

	external_url="$1"

	# get external ip from website
	external_ip=$(curl --connect-timeout 5 --max-time 10 --retry 3 --retry-max-time 30 -s "${external_url}" |  jq -r '.ip')

	echo "${external_ip}"
	return 0
}

# create function to check local ip adress for tunnel is valid
check_valid_ip() {

	local_vpn_ip="$1"

	# check if the format looks right
	echo "${local_vpn_ip}" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octect is less than or equal to 255
	echo "${local_vpn_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	return 0
}

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Waiting for valid IP address from tunnel..."
fi

# loop and wait until tunnel adapter local ip is valid
current_vpn_ip=""
while ! check_valid_ip "${current_vpn_ip}"
do
	sleep 0.1
	current_vpn_ip=$(ifconfig "${VPN_DEVICE_TYPE}0" 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
done

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Valid IP address from tunnel acquired '${current_vpn_ip}'"
fi

vpn_ip="${current_vpn_ip}"

# run function to get external ip address from ext site
external_ip="$(get_external_ip "${pri_external_ip_website}")"
exit_code="${?}"

# if function returns error then try alt ext site
if [ "${exit_code}" != "0" ]; then

	echo "[warn] Cannot determine external IP address from '${pri_external_ip_website}', trying alternative site..."

	external_ip="$(get_external_ip "${sec_external_ip_website}")"
	exit_code="${?}"

	if [ "${exit_code}" != "0" ]; then

		echo "[warn] Cannot determine external IP address, possible connection issues at present."

		external_ip="0.0.0.0"
		return 1

	fi

fi

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] External IP address from tunnel is '${external_ip}'"
fi
