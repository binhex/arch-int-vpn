#!/bin/bash

echo "[info] Starting OpenVPN..."

# set sleep period for recheck (in mins)
sleep_period="10"

# loop and restart openvpn on exit
while true; do

	openvpn_cli="/usr/bin/openvpn --cd /config/openvpn --config "${VPN_CONFIG}" --remote "${VPN_REMOTE}" "${VPN_PORT}" --proto "${VPN_PROTOCOL}" --reneg-sec 0 --mute-replay-warnings --auth-nocache --keepalive 10 60"

	if [[ "${VPN_PROV}" == "pia" ]]; then

		# add additional flags to pass credentials and ignore local-remote warnings
		openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf --disable-occ"


	elif [[ "${VPN_PROV}" != "airvpn" ]]; then

		# add additional flags to pass credentials
		openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

	fi

	# run openvpn to create tunnel
	eval "${openvpn_cli}"

	echo "[warn] VPN connection terminated"

	# kill process openvpn
	/usr/bin/pkill openvpn

	echo "[warn] Restarting VPN connection in ${sleep_period} mins"
	sleep "${sleep_period}"m

done
