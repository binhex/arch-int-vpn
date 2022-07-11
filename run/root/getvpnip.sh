#!/bin/bash

# function to check ip address is in valid format (used for local tunnel ip and external ip)
check_valid_ip() {

	local_vpn_ip="$1"

	# check if the format looks right
	echo "${local_vpn_ip}" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octet is less than or equal to 255
	echo "${local_vpn_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	# check ip is not loopback or link local
	echo "${local_vpn_ip}" | grep '127.0.0.1' && return 1
	echo "${local_vpn_ip}" | egrep -qE '169\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' && return 1

	return 0
}

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Waiting for valid local and gateway IP addresses from tunnel..."
fi

# loop and wait until tunnel adapter local ip is valid
vpn_ip=""
while ! check_valid_ip "${vpn_ip}"; do

	vpn_ip=$(ifconfig "${VPN_DEVICE_TYPE}" 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
	sleep 1s

done

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Valid local IP address from tunnel acquired '${vpn_ip}'"
fi

if [[ "${VPN_PROV}" == "pia" ]]; then

	# if empty get gateway ip (openvpn clients), otherwise skip (defined in wireguard.sh)
	if [[ -z "${vpn_gateway_ip}" ]]; then

		# get gateway ip, used for openvpn and wireguard to get port forwarding working via getvpnport.sh
		vpn_gateway_ip=""
		while ! check_valid_ip "${vpn_gateway_ip}"; do

			vpn_gateway_ip=$(ip route s t all | grep -m 1 "0.0.0.0/1 via .* dev ${VPN_DEVICE_TYPE}" | cut -d ' ' -f3)
			sleep 1s

		done

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Valid gateway IP address from tunnel acquired '${vpn_gateway_ip}'"
	fi

fi

echo "${vpn_ip}" > /tmp/getvpnip
