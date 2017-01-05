#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --cd /config/openvpn --config "${VPN_CONFIG}" ==daemon --remote "${VPN_REMOTE}" "${VPN_PORT}" --proto "${VPN_PROTOCOL}" --reneg-sec 0 --mute-replay-warnings --auth-nocache --keepalive 10 60"

if [[ "${VPN_PROV}" == "pia" ]]; then

	# add additional flags to pass credentials and ignore local-remote warnings
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf --disable-occ"

elif [[ "${VPN_PROV}" != "airvpn" ]]; then

	# add additional flags to pass credentials
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

fi

echo "[info] Starting OpenVPN..."

# run openvpn to create tunnel (daemonized)
eval "${openvpn_cli}"

# set sleep period for recheck (in secs)
sleep_period="30"

# loop and restart openvpn on process termination
while true; do

	# check if openvpn is running, if not then start and kill sleep process for downloader shell
	if ! pgrep -f /usr/bin/openvpn > /dev/null; then

		echo "[warn] OpenVPN process not running, restarting..."

		# run openvpn to create tunnel
		eval "${openvpn_cli}"

		echo "[info] OpenVPN restarted, killing sleep process for downloader to force ip/port refresh..."
		pkill -P $(</home/nobody/downloader.sleep.pid) sleep
		echo "[info] Sleep process killed"

		# sleep for 1 min to give openvpn chance to start before re-checking
		sleep 1m

	fi

	sleep "${sleep_period}"s

done
