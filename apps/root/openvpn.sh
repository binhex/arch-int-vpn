#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --cd /config/openvpn --config "${VPN_CONFIG}" --daemon --remote "${VPN_REMOTE}" "${VPN_PORT}" --proto "${VPN_PROTOCOL}" --reneg-sec 0 --mute-replay-warnings --auth-nocache --keepalive 10 60"

if [[ "${VPN_PROV}" == "pia" ]]; then

	# add additional flags to pass credentials and ignore local-remote warnings
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf --disable-occ"

elif [[ "${VPN_PROV}" != "airvpn" ]]; then

	# add additional flags to pass credentials
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

fi

# run openvpn to create tunnel (daemonized)
echo "[info] Starting OpenVPN..."
eval "${openvpn_cli}"
echo "[info] OpenVPN started"

# sleep to give openvpn process chance to start
sleep 10s

# define location and name of pid file
pid_file="/home/nobody/downloader.sleep.pid"

# set sleep period for recheck (in secs)
sleep_period="10"

# loop and restart openvpn on process termination
while true; do

	# check if openvpn is running, if not then restart and kill sleep process for downloader shell
	if ! pgrep -f /usr/bin/openvpn > /dev/null; then

		echo "[warn] OpenVPN process terminated, restarting OpenVPN..."
		eval "${openvpn_cli}"
		echo "[info] OpenVPN restarted"

		if [[ -f "${pid_file}" ]]; then

			echo "[info] Killing sleep command in rtorrent.sh to force refresh of ip/port..."
			pkill -P $(<"${pid_file}") sleep
			echo "[info] Refresh process started"

		else

			echo "[info] No PID file containing PID for sleep command in rtorrent.sh present, assuming script hasn't started yet."

		fi

	fi

	sleep "${sleep_period}"s

done
