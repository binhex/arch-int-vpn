#!/bin/bash

echo "[info] Starting OpenVPN..."

# set sleep period for recheck (in mins)
sleep_period="10"

# loop and restart openvpn on exit
while true; do

	if [[ "${VPN_PROV}" != "airvpn" ]]; then

		# run openvpn to create tunnel
		/usr/bin/openvpn --cd /config/openvpn --config "$VPN_CONFIG" --remote "${VPN_REMOTE}" "${VPN_PORT}" --proto "${VPN_PROTOCOL}" --reneg-sec 0 --auth-user-pass credentials.conf --mute-replay-warnings --keepalive 10 60

	else

		# run openvpn to create tunnel (airvpn uses certs for auth thus no --auth-user-pass)
		/usr/bin/openvpn --cd /config/openvpn --config "$VPN_CONFIG" --remote "${VPN_REMOTE}" "${VPN_PORT}" --proto "${VPN_PROTOCOL}" --reneg-sec 0 --mute-replay-warnings --keepalive 10 60

	fi

	echo "[warn] VPN connection terminated"

	# kill process openvpn
	/usr/bin/pkill openvpn

	echo "[warn] Restarting VPN connection in ${sleep_period} mins"
	sleep "${sleep_period}"m

done
