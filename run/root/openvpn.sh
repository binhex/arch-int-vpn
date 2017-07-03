#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --cd /config/openvpn --config ${VPN_CONFIG} --daemon --dev ${VPN_DEVICE_TYPE}0 --remote ${VPN_REMOTE} ${VPN_PORT} --proto ${VPN_PROTOCOL} --reneg-sec 0 --mute-replay-warnings --auth-nocache --keepalive 10 60 --setenv VPN_PROV ${VPN_PROV} --setenv DEBUG ${DEBUG} --script-security 2 --up /root/openvpnup.sh --up-delay --up-restart --writepid /root/openvpn.pid"

if [[ "${VPN_PROV}" == "pia" ]]; then

	# add additional flags to pass credentials and ignore local-remote warnings
	openvpn_cli="${openvpn_cli} --setenv STRICT_PORT_FORWARD ${STRICT_PORT_FORWARD} --auth-user-pass credentials.conf --disable-occ --remap-usr1 SIGHUP --log-append /dev/stdout"

fi

if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

	# add additional flags to pass credentials
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

fi

if [[ ! -z "${VPN_OPTIONS}" ]]; then

	# add additional flags to openvpn cli
	openvpn_cli="${openvpn_cli} ${VPN_OPTIONS}"

fi

if [[ "${DEBUG}" == "true" ]]; then

	echo "[debug] OpenVPN command line '${openvpn_cli}'"

fi

# run openvpn to create tunnel (daemonized)
echo "[info] Starting OpenVPN..."
eval "${openvpn_cli}"
echo "[info] OpenVPN started"

# run script to check ip is valid for tunnel device (will block until valid)
source /home/nobody/getvpnip.sh

# set sleep period for recheck (in secs)
sleep_period="30"

# loop and restart openvpn on process termination
while true; do

	# check if openvpn is running, if not then restart
	if ! pgrep -x openvpn > /dev/null; then

		echo "[warn] OpenVPN process terminated, restarting OpenVPN..."
		eval "${openvpn_cli}"
		echo "[info] OpenVPN restarted"

	fi

	sleep "${sleep_period}"s

done
