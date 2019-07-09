#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --daemon --reneg-sec 0 --mute-replay-warnings --auth-nocache --setenv VPN_PROV '${VPN_PROV}' --setenv DEBUG '${DEBUG}' --setenv VPN_DEVICE_TYPE '${VPN_DEVICE_TYPE}' --setenv VPN_ENABLED '${VPN_ENABLED}' --setenv VPN_REMOTE '${VPN_REMOTE}' --setenv APPLICATION '${APPLICATION}' --script-security 2 --writepid /root/openvpn.pid --remap-usr1 SIGHUP --log-append /dev/stdout --pull-filter ignore 'up' --pull-filter ignore 'down' --pull-filter ignore 'route-ipv6' --pull-filter ignore 'ifconfig-ipv6' --pull-filter ignore 'tun-ipv6' --pull-filter ignore 'persist-tun' --pull-filter ignore 'reneg-sec' --up /root/openvpnup.sh --up-delay --up-restart"

# check answer is not blank, generated in start.sh, if it is blank assume bad ns or ${VPN_REMOTE} is an ip address
if [[ ! -z "${remote_dns_answer}" ]]; then

	# split space separated string into list from remote_dns_answer
	IFS=' ' read -ra remote_dns_answer_list <<< "${remote_dns_answer}"

	# iterate through list of ip addresses and add each ip as a --remote option to ${openvpn_cli}
	for vpn_remote_ip in "${remote_dns_answer_list[@]}"; do
		openvpn_cli="${openvpn_cli} --remote ${vpn_remote_ip} ${VPN_PORT} ${VPN_PROTOCOL}"
	done

	# randomize the --remote option that openvpn will use to connect. this should help
	# prevent getting stuck on a particular endpoint should it become unstable/unavailable
	openvpn_cli="${openvpn_cli} --remote-random"

fi

if [[ -z "${vpn_ping}" ]]; then

	# if no ping options in the ovpn file then specify keepalive option
	openvpn_cli="${openvpn_cli} --keepalive 10 60"

fi

if [[ "${VPN_PROV}" == "pia" ]]; then

	# add pia specific flags
	openvpn_cli="${openvpn_cli} --setenv STRICT_PORT_FORWARD '${STRICT_PORT_FORWARD}' --disable-occ"

fi

if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

	# add additional flags to pass credentials
	openvpn_cli="${openvpn_cli} --auth-user-pass credentials.conf"

fi

if [[ ! -z "${VPN_OPTIONS}" ]]; then

	# add additional flags to openvpn cli
	# note do not single/double quote the variable VPN_OPTIONS
	openvpn_cli="${openvpn_cli} ${VPN_OPTIONS}"

fi

# finally add options specified in ovpn file
openvpn_cli="${openvpn_cli} --cd /config/openvpn --config '${VPN_CONFIG}'"

if [[ "${DEBUG}" == "true" ]]; then

	echo "[debug] OpenVPN command line:- ${openvpn_cli}"

fi

# run openvpn to create tunnel (daemonized)
echo "[info] Starting OpenVPN..."
eval "${openvpn_cli}"
echo "[info] OpenVPN started"

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
