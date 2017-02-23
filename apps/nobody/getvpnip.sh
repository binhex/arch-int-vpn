#!/bin/bash

# function to check ip adress is in valid format (used for local tunnel ip and external ip)
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

# define name servers to connect to in order to get external ip address
pri_external_ip_ns="ns1.google.com"
sec_external_ip_ns="resolver1.opendns.com"

# use dns query to get external ip address
external_ip="$(dig TXT +short o-o.myaddr.l.google.com @${pri_external_ip_ns} | tr -d '"')"
check_valid_ip "${external_ip}"
exit_code="${?}"

# if error then try secondary name server
if [[ "${exit_code}" != 0 ]]; then

	echo "[warn] Cannot determine external IP address from '${pri_external_ip_ns}', trying alternative name server..."

	external_ip="$(dig +short myip.opendns.com @${sec_external_ip_ns})"
	check_valid_ip "${external_ip}"
	exit_code="${?}"

	if [[ "${exit_code}" != 0 ]]; then

		echo "[warn] Cannot determine external IP address from '${sec_external_ip_ns}', possible connection issues at present."

		external_ip="0.0.0.0"
		return 1

	fi

fi

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] External IP address from tunnel is '${external_ip}'"
fi
