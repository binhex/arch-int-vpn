#!/bin/bash

# create function to get the external ip address for tunnel
get_external_ip() {

	external_url="$1"

	# get external ip from website
	external_ip=$(curl -L "${external_url}" -s |  jq -r '.ip' || return 1 )

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

echo "[info] Waiting for valid IP address from tunnel..."

# loop and wait until tunnel adapter local ip is valid
current_vpn_ip=""
while ! check_valid_ip "${current_vpn_ip}"
do
	sleep 0.1
	current_vpn_ip=$(ifconfig "${VPN_DEVICE_TYPE}0" 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
done

echo "[info] Valid IP address from tunnel acquired '${current_vpn_ip}'"
vpn_ip="${current_vpn_ip}"

# run function to get external ip address from ext site
external_ip="$(get_external_ip "https://api.ipify.org/?format=json")"
exit_code="${?}"

# if function returns error then try alt ext site
if [ "${exit_code}" != "0" ]; then
	external_ip="$(get_external_ip "https://jsonip.com/")"
	exit_code="${?}"

	if [ "${exit_code}" != "0" ]; then
		echo "[info] Cannot determine external IP address, possible connection issues at present."
		external_ip="0.0.0.0"
		return 1
	fi

fi

echo "[info] External IP address from tunnel is '${external_ip}'"
