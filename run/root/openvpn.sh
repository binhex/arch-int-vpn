#!/bin/bash

# define common command lne parameters for openvpn
openvpn_cli="/usr/bin/openvpn --daemon --reneg-sec 0 --mute-replay-warnings --auth-nocache --setenv VPN_PROV '${VPN_PROV}' --setenv DEBUG '${DEBUG}' --setenv VPN_DEVICE_TYPE '${VPN_DEVICE_TYPE}' --setenv VPN_ENABLED '${VPN_ENABLED}' --setenv VPN_REMOTE '${VPN_REMOTE}' --setenv APPLICATION '${APPLICATION}' --script-security 2 --writepid /root/openvpn.pid --remap-usr1 SIGHUP --log-append /dev/stdout --pull-filter ignore 'up' --pull-filter ignore 'down' --pull-filter ignore 'route-ipv6' --pull-filter ignore 'ifconfig-ipv6' --pull-filter ignore 'tun-ipv6' --pull-filter ignore 'dhcp-option DNS6' --pull-filter ignore 'persist-tun' --pull-filter ignore 'reneg-sec' --up /root/openvpnup.sh --up-delay --up-restart"

# For backward compatibility, allow $remote_dns_answer corresponding to $VPN_REMOTE, $VPN_PORT, and $VPN_PROTOCOL

# $remote_dns_answers_list with $VPN_REMOTE_LIST, $VPN_PORT_LIST, and $VPN_PROTOCOL_LIST (all arrays) are the replacement.
# remote_dns_answers_list[x] should be an empty string or the ip address if $VPN_REMOTE_LIST[x] was an ip address
# These are read from files since arrays cannot be exported

if [ -e /config/openvpn/vpnremotelist ] ; then
	# retrieve the VPN_REMOTE_LIST, VPN_PROTOCOL_LIST, and VPN_PORT_LIST
	readarray VPN_REMOTE_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $1}')
	readarray VPN_PORT_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $2}')
	readarray VPN_PROTOCOL_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $3}')
    for i in $(seq 0 $((${#VPN_REMOTE_LIST[@]} - 1))) ; do
        VPN_REMOTE_LIST[$i]=$(echo "${VPN_REMOTE_LIST[$i]}" | tr -d '[:space:]')
        VPN_PORT_LIST[$i]=$(echo "${VPN_PORT_LIST[$i]}" | tr -d '[:space:]')
        VPN_PROTOCOL_LIST[$i]=$(echo "${VPN_PROTOCOL_LIST[$i]}" | tr -d '[:space:]')
    done
fi
if [ -e  /tmp/vpnremotednsanswers ] ; then
	# retrieve the remote_dns_answers_list
	readarray remote_dns_answers_list < <(cat  /tmp/vpnremotednsanswers)
    for i in $(seq 0 $((${#remote_dns_answers_list[@]} - 1))) ; do
        readarray_remote_dns_answers_list[$i]=$(echo "${readarray_remote_dns_answers_list[$i]}" | tr -d '[:space:]')
    done
fi



# check answer is not blank, generated in start.sh, if it is blank assume bad ns or ${VPN_REMOTE} is an ip address

## Adds the "--remote ipaddr port protocol" lines to ${openvpn_cli}
# Args:
#  1: quoted string for the remote DNS answer containing a space-separated list of IP address corresponding to the VPN server name
#  2: VPN port for the name
#  3: Protocol (tcp or udp)
# Return: 0 if any IP addresses were parsed, 1 otherwise
add_openvpn_remote() {
	local port=${2}
	local protocol=${3}
	local remote_dns_answer_list
	local vpn_remote_ip
	local ret=1

	if [[ ! -z "${1}" ]]; then
		# split space separated string into list from remote_dns_answer
		IFS=' ' read -ra remote_dns_answer_list <<< "${1}"

		# iterate through list of ip addresses and add each ip as a --remote option to ${openvpn_cli}
		for vpn_remote_ip in "${remote_dns_answer_list[@]}"; do
			openvpn_cli="${openvpn_cli} --remote ${vpn_remote_ip} ${port} ${protocol}"
			ret=0
		done
	fi

	return $ret
}

remote_random=false
if [ ${#remote_dns_answers_list[@]} -gt 0 ] ; then
	for i in $(seq 0 $((${#remote_dns_answers_list[@]} - 1))) ; do
		if add_openvpn_remote "${remote_dns_answers_list[$i]}" "${VPN_PORT_LIST[$i]}" "${VPN_PROTOCOL_LIST[$i]}" ; then
			remote_random=true
		fi
	done
else
	if add_openvpn_remote "${remote_dns_answer}" "${VPN_PORT}" "${VPN_PROTOCOL}" ; then
		remote_random=true
	fi
fi

if $remote_random ; then
	# randomize the --remote option that openvpn will use to connect. this should help
	# prevent getting stuck on a particular server should it become unstable/unavailable
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
sleep_period_secs="30"

# loop and restart openvpn on process termination
while true; do

	# if '/tmp/portclosed' file exists (generated by /home/nobody/watchdog.sh when incoming port
	# detected as closed) then terminate openvpn to force refresh of port
	if [ -f "/tmp/portclosed" ];then

		echo "[info] Sending SIGTERM (-15) to 'openvpn' due to port closed..."
		pkill -SIGTERM "openvpn"
		rm -f "/tmp/portclosed"

	fi

	# if '/tmp/dnsfailure' file exists (generated by /home/nobody/checkdns.sh when name resolution
	# failed) then terminate openvpn to force refresh of port
	if [ -f "/tmp/dnsfailure" ];then

		echo "[info] Sending SIGTERM (-15) to 'openvpn' due to name resolution failure..."
		pkill -SIGTERM "openvpn"
		rm -f "/tmp/dnsfailure"

	fi

	# check if openvpn is running, if not then restart
	if ! pgrep -x openvpn > /dev/null; then

		echo "[warn] OpenVPN process terminated, restarting OpenVPN..."
		eval "${openvpn_cli}"
		echo "[info] OpenVPN restarted"

	fi

	sleep "${sleep_period_secs}"s

done
