#!/bin/bash

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of VPN"

else

	echo "[info] VPN is enabled, beginning configuration of VPN"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Environment variables defined as follows" ; set
		echo "[debug] Directory listing of files in /config/openvpn as follows" ; ls -al /config/openvpn
		echo "[debug] VPN Remote list"
		[ -e /config/openvpn/vpnremotelist ] && cat /config/openvpn/vpnremotelist
	fi

	# if vpn username and password specified then write credentials to file (authentication maybe via keypair)
	if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

		# store credentials in separate file for authentication
		if ! $(grep -Fq "auth-user-pass credentials.conf" "${VPN_CONFIG}"); then
			sed -i -E -e 's/(auth-user-pass.*)/auth-user-pass credentials.conf\n#\1/g' "${VPN_CONFIG}" || true
		fi

		echo "${VPN_USER}" > /config/openvpn/credentials.conf

		username_char_check=$(echo "${VPN_USER}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${username_char_check}" ]]; then
			echo "[warn] Username contains characters which could cause authentication issues, please consider changing this if possible"
		fi

		echo "${VPN_PASS}" >> /config/openvpn/credentials.conf

		password_char_check=$(echo "${VPN_PASS}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${password_char_check}" ]]; then
			echo "[warn] Password contains characters which could cause authentication issues, please consider changing this if possible"
		fi

	fi

	# note - do not remove redirection of gateway for ipv6 - required for certain vpn providers (airvpn)

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	sed -i -E 's/(^persist-tun)/#\1/' "${VPN_CONFIG}" || true

	# remove reneg-sec from ovpn file if present, this is removed to prevent re-checks and dropouts
	sed -i -E 's/(^reneg-sec.*)/#\1/' "${VPN_CONFIG}" || true

	# remove up script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
	sed -i -E 's/(^up\s.*)/#\1/' "${VPN_CONFIG}" || true

	# remove down script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
	sed -i -E 's/(^down\s.*)/#\1/' "${VPN_CONFIG}" || true

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i -E 's/(^route-ipv6)/#\1/' "${VPN_CONFIG}" || true

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i -E 's/(^ifconfig-ipv6)/#\1/' "${VPN_CONFIG}" || true

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i -E 's/(^tun-ipv6)/#\1/' "${VPN_CONFIG}" || true

	# remove dhcp option for dns ipv6 configuration from ovpn file if present (dns defined via name_server env var value)
	sed -i -E 's/(^dhcp-option DNS6.*)/#\1/' "${VPN_CONFIG}" || true

	# remove redirection of gateway for ipv4/ipv6 from ovpn file if present (we want a consistent gateway set)
	sed -i -E 's/(^redirect-gateway.*)/#\1/' "${VPN_CONFIG}"

	# remove windows specific openvpn options
	sed -i -E 's/(^route-method exe)/#\1/' "${VPN_CONFIG}" || true
	sed -i -E 's/(^service\s.*)/#\1/' "${VPN_CONFIG}" || true
	sed -i -E 's/(^block-outside-dns)/#\1/' "${VPN_CONFIG}" || true

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
	fi

	# assign any matching ping options in ovpn file to variable (used to decide whether to specify --keealive option in openvpn.sh)
	vpn_ping=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '^ping.*')

	# forcibly set virtual network device to 'tun0/tap0' (referenced in iptables)
	sed -i -E "s/(^dev\s${VPN_DEVICE_TYPE}.*)/dev ${VPN_DEVICE_TYPE}\n#\1/g" "${VPN_CONFIG}"  || true

	# get ip for local gateway (eth0)
	DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')
	echo "[info] Default route for container is ${DEFAULT_GATEWAY}"

	# split comma seperated string into list from NAME_SERVERS env variable
	IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

	# remove existing ns, docker injects ns from host and isp ns can block/hijack
	> /etc/resolv.conf

	# process name servers in the list
	for name_server_item in "${name_server_list[@]}"; do

		# strip whitespace from start and end of name_server_item
		name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "[info] Adding ${name_server_item} to /etc/resolv.conf"
		echo "nameserver ${name_server_item}" >> /etc/resolv.conf

	done

	# Set the $remote_dns_answer to the space separated list of ip addresses resolved from
	# a VPN server name.  Skips VPN server names that are already IP addresses.
	# Retries the DNS resolution up to 12 times with a 5 second delay in between each attempt
	# if a look up fails.  After 12 failures it throws an error and exits
	# Args:
	#  1: Servername or IP address of VPN remote
	# Return: sets $remote_dns_answer to the space separated list of resolved IP addresses
	get_remote_dns_resolution() {
		local vpn_remote="${1}"
		local retry_count
		local remote_dns_answer_first

		# is it already an IP address?
		if ! echo "${vpn_remote}" | grep -P -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
			retry_count=12

			# do-while, no resolution and haven't hit retry limit
			while [ -z "${remote_dns_answer}" ] && [ "${retry_count}" -gt "0" ]; do
				# attempt to look up the DNS resolution, limiting to 63 IPv4 responses
				remote_dns_answer=$(drill -a -4 "${vpn_remote}" | grep -v 'SERVER' | grep -m 63 -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)
				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Failed to resolve endpoint '${vpn_remote}' retrying..."
				fi
				if [ -z "${remote_dns_answer}" ] ; then
					retry_count=$((retry_count-1))
					sleep 5s
				fi
			done

			# stopped because of retry limit?
			if [ "${retry_count}" -eq "0" ]; then
				echo "[crit] '${vpn_remote}' cannot be resolved, possible DNS issues, exiting..." ; exit 1
			fi

			# get first ip from remote_dns_answer and write to the hosts file
			# this is required as openvpn will use the remote entry in the ovpn file
			# even if you specify the --remote options on the command line, and thus we
			# must also be able to resolve the host name (assuming it is a name and not ip).
			remote_dns_answer_first=$(echo "${remote_dns_answer}" | cut -d ' ' -f 1)

			# if not blank then write to hosts file
			if [[ ! -z "${remote_dns_answer_first}" ]]; then
				echo "${remote_dns_answer_first}	${vpn_remote}" >> /etc/hosts
			fi
		else # was already an ip address
			remote_dns_answer="${1}"
		fi
	}

	# couldn't export, so load from file
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

	# parse the VPN_REMOTE_LIST into an array of lists of space separated ip addresses
	if [ ${#VPN_REMOTE_LIST[@]} -gt 0 ] ; then
		for i in $(seq 0 $((${#VPN_REMOTE_LIST[@]} - 1))) ; do
			get_remote_dns_resolution "${VPN_REMOTE_LIST[$i]}"
			remote_dns_answers_list[$i]="${remote_dns_answer}"
			echo "${remote_dns_answer}" >> /tmp/vpnremotednsanswers
		done
		# need to set this always, pick the first one
		export remote_dns_answer_first=$(echo "${remote_dns_answers_list[0]}" | cut -d ' ' -f 1)
	elif [[ -n "${VPN_REMOTE}" ]] ; then
		# VPN_REMOTE is deprecated, but for backward compatibility we leave $remote_dns_answer
		# set to what VPN_REMOTE resolves to
		get_remote_dns_resolution "${VPN_REMOTE}"
		# need to set this always
		export remote_dns_answer_first=$(echo "${remote_dns_answer}" | cut -d ' ' -f 1)
	fi

	# check if we have tun module available
	check_tun_available=$(lsmod | grep tun)

	# if tun module not available then try installing it
	if [[ -z "${check_tun_available}" ]]; then
		echo "[info] Attempting to load tun kernel module..."
		/sbin/modprobe tun
		tun_module_exit_code=$?
		if [[ $tun_module_exit_code != 0 ]]; then
			echo "[warn] Unable to load tun kernel module using modprobe, trying insmod..."
			insmod /lib/modules/tun.ko
			tun_module_exit_code=$?
			if [[ $tun_module_exit_code != 0 ]]; then
				echo "[warn] Unable to load tun kernel module, assuming its dynamically loaded"
			fi
		fi
	fi

	# create the tunnel device if not present (unraid users do not require this step)
	mkdir -p /dev/net
	[ -c "/dev/net/tun" ] || mknod "/dev/net/tun" c 10 200
	tun_create_exit_code=$?
	if [[ $tun_create_exit_code != 0 ]]; then
		echo "[crit] Unable to create tun device, try adding docker container option '--device=/dev/net/tun'" ; exit 1
	else
		chmod 600 /dev/net/tun
	fi

	# check if we have iptable_mangle module available
	check_mangle_available=$(lsmod | grep iptable_mangle)

	# if mangle module not available then try installing it
	if [[ -z "${check_mangle_available}" ]]; then
		echo "[info] Attempting to load iptable_mangle module..."
		/sbin/modprobe iptable_mangle
		mangle_module_exit_code=$?
		if [[ $mangle_module_exit_code != 0 ]]; then
			echo "[warn] Unable to load iptable_mangle module using modprobe, trying insmod..."
			insmod /lib/modules/iptable_mangle.ko
			mangle_module_exit_code=$?
			if [[ $mangle_module_exit_code != 0 ]]; then
				echo "[warn] Unable to load iptable_mangle module, you will not be able to connect to the applications Web UI or Privoxy outside of your LAN"
				echo "[info] unRAID/Ubuntu users: Please attempt to load the module by executing the following on your host: '/sbin/modprobe iptable_mangle'"
				echo "[info] Synology users: Please attempt to load the module by executing the following on your host: 'insmod /lib/modules/iptable_mangle.ko'"
			fi
		fi
	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Show name servers defined for container" ; cat /etc/resolv.conf
		if [[ -n "${VPN_REMOTE}" ]] || [ ${#VPN_REMOTE_LIST[@]} -gt 0 ] ; then
			echo "[debug] Show name resolution for VPN endpoints:"
			if [ ${#VPN_REMOTE_LIST[@]} -gt 0 ] ; then
				for i in $(seq 0 $((${#VPN_REMOTE_LIST[@]} - 1))) ; do
					echo "            ${VPN_REMOTE_LIST[$i]} = ${remote_dns_answers_list[$i]}"
				done
			fi
			elif [[ -n "${VPN_REMOTE}" ]] ; then
				echo "            ${VPN_REMOTE} = ${remote_dns_answer}"
			fi
		fi
		echo "[debug] Show contents of hosts file" ; cat /etc/hosts
	fi

	# setup ip tables and routing for application
	source /root/iptable.sh

	# start openvpn tunnel
	source /root/openvpn.sh

fi
