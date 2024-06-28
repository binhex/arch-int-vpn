#!/bin/bash

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of VPN"

else

	echo "[info] VPN is enabled, beginning configuration of VPN"

	if [[ "${VPN_CLIENT}" == "openvpn" ]]; then

		# if vpn username and password specified then write credentials to file (authentication maybe via keypair)
		if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

			# store credentials in separate file for authentication
			if ! $(grep -Fq "auth-user-pass credentials.conf" "${VPN_CONFIG}"); then
				sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "${VPN_CONFIG}"
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

		# remove keysize from ovpn file if present, deprecated and now removed option
		sed -i '/^keysize.*/d' "${VPN_CONFIG}"

		# remove ncp-disable from ovpn file if present, deprecated and now removed option
		sed -i '/^ncp-disable/d' "${VPN_CONFIG}"

		# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
		sed -i '/^persist-tun/d' "${VPN_CONFIG}"

		# remove reneg-sec from ovpn file if present, this is removed to prevent re-checks and dropouts
		sed -i '/^reneg-sec.*/d' "${VPN_CONFIG}"

		# remove up script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
		sed -i '/^up\s.*/d' "${VPN_CONFIG}"

		# remove down script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
		sed -i '/^down\s.*/d' "${VPN_CONFIG}"

		# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
		sed -i '/^route-ipv6/d' "${VPN_CONFIG}"

		# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
		sed -i '/^ifconfig-ipv6/d' "${VPN_CONFIG}"

		# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
		sed -i '/^tun-ipv6/d' "${VPN_CONFIG}"

		# remove dhcp option for dns ipv6 configuration from ovpn file if present (dns defined via name_server env var value)
		sed -i '/^dhcp-option DNS6.*/d' "${VPN_CONFIG}"

		# remove windows specific openvpn options
		sed -i '/^route-method exe/d' "${VPN_CONFIG}"
		sed -i '/^service\s.*/d' "${VPN_CONFIG}"
		sed -i '/^block-outside-dns/d' "${VPN_CONFIG}"

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
		fi

		# assign any matching ping options in ovpn file to variable (used to decide whether to specify --keealive option in openvpn.sh)
		vpn_ping=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '^ping.*')

		# forcibly set virtual network device to 'tun0/tap0' (referenced in iptables)
		sed -i "s/^dev\s${VPN_DEVICE_TYPE}.*/dev ${VPN_DEVICE_TYPE}/g" "${VPN_CONFIG}"

	fi

	if [[ "${DEBUG}" == "true" ]]; then

		echo "[debug] Environment variables defined as follows" ; set

		if [[ "${VPN_CLIENT}" == "openvpn" ]]; then

			echo "[debug] Directory listing of files in /config/openvpn/ as follows" ; ls -al '/config/openvpn'
			echo "[debug] Contents of OpenVPN config file '${VPN_CONFIG}' as follows..." ; cat "${VPN_CONFIG}"

		else

			echo "[debug] Directory listing of files in /config/wireguard/ as follows" ; ls -al '/config/wireguard'

			if [ -f "${VPN_CONFIG}" ]; then
				echo "[debug] Contents of WireGuard config file '${VPN_CONFIG}' as follows..." ; cat "${VPN_CONFIG}"
			else
				echo "[debug] File path '${VPN_CONFIG}' does not exist, skipping displaying file content"
			fi

		fi

	fi

	# workaround for pia CRL issue
	if [[ "${VPN_CLIENT}" == "openvpn" ]]; then

		if [[ "${VPN_PROV}" == "pia" ]]; then

			# turn off compression, required to bypass pia crl-verify issue with pia
			# see https://github.com/binhex/arch-qbittorrentvpn/issues/233
			sed -i -e 's~^compress~comp-lzo no~g' "${VPN_CONFIG}"

			# remove crl-verify as pia verification has invalid date
			# see https://github.com/binhex/arch-qbittorrentvpn/issues/233
			sed -i '/<crl-verify>/,/<\/crl-verify>/d' "${VPN_CONFIG}"

		fi

	fi

	if [[ "${VPN_CLIENT}" == "openvpn" ]]; then

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

		# iterate over array of remote servers
		for index in "${!vpn_remote_server_list[@]}"; do
			echo "[debug] Show name resolution for VPN endpoint ${vpn_remote_server_list[$index]}" ; drill -a "${vpn_remote_server_list[$index]}"
		done

		echo "[debug] Show contents of hosts file" ; cat /etc/hosts
	fi

	if [[ "${VPN_CLIENT}" == "openvpn" ]]; then

		# start openvpn client
		source /root/openvpn.sh

	elif [[ "${VPN_CLIENT}" == "wireguard" ]]; then

		# start wireguard client
		source /root/wireguard.sh

	fi

fi
