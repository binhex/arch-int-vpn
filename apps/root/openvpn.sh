#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --cd /config/openvpn --config ${VPN_CONFIG} --daemon --dev ${VPN_DEVICE_TYPE}0 --remote ${VPN_REMOTE} ${VPN_PORT} --proto ${VPN_PROTOCOL} --reneg-sec 0 --mute-replay-warnings --auth-nocache --keepalive 10 60"

if [[ "${VPN_PROV}" == "pia" ]]; then

	# add additional flags to pass credentials and ignore local-remote warnings
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf --disable-occ"

elif [[ "${VPN_PROV}" != "airvpn" ]]; then

	# add additional flags to pass credentials
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

fi

if [[ ! -z "${VPN_OPTIONS}" ]]; then

	# add additional flags to openvpn cli
	openvpn_cli="${openvpn_cli} ${VPN_OPTIONS}"

fi

if [[ "${DEBUG}" == "true" ]]; then
	echo "OpenVPN command line '${openvpn_cli}'"
fi

# run openvpn to create tunnel (daemonized)
echo "[info] Starting OpenVPN..."
eval "${openvpn_cli}"
echo "[info] OpenVPN started"

# run script to check ip is valid for tunnel device (will block until valid)
source /home/nobody/getvpnip.sh

# define location and name of pid file
pid_file="/home/nobody/downloader.sleep.pid"

# set sleep period for recheck (in secs)
sleep_period="30"

# loop and restart openvpn on process termination
while true; do

	# check if openvpn is running, if not then restart and kill sleep process for downloader shell
	if ! pgrep -f /usr/bin/openvpn > /dev/null; then

		echo "[warn] OpenVPN process terminated, restarting OpenVPN..."
		eval "${openvpn_cli}"
		echo "[info] OpenVPN restarted"

		sleep "${sleep_period}"s

		if [[ -f "${pid_file}" ]]; then

			echo "[info] Killing sleep command in rtorrent.sh to force refresh of ip/port..."
			pkill -P $(<"${pid_file}") sleep
			echo "[info] Refresh process started"

		fi

	fi

	sleep "${sleep_period}"s

done
