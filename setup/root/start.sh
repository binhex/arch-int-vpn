#!/bin/bash

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of VPN"

else

	echo "[info] VPN is enabled, beginning configuration of VPN"

	# create directory to store openvpn config files
	mkdir -p /config/openvpn

	# set perms and owner for openvpn directory
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	exit_code_chown=$?
	chmod -R 777 "/config/openvpn" &> /dev/null
	exit_code_chmod=$?

	# wildcard search for openvpn config files (match on first result)
	VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

	# if ovpn filename is not custom.ovpn and the provider is pia then copy included ovpn and certs
	if [[ "${VPN_CONFIG}" != "/config/openvpn/custom.ovpn" && "${VPN_PROV}" == "pia" ]]; then

		# remove previous certs and ovpn files, user may of switched to strong
		rm -f /config/openvpn/*

		if [[ "${STRONG_CERTS}" == "yes" ]]; then

			echo "[info] VPN strong certs defined, copying to /config/openvpn/..."

			# copy strong encrption ovpn and certs
			cp -f /home/nobody/certs/strong/*.crt /config/openvpn/
			cp -f /home/nobody/certs/strong/*.pem /config/openvpn/
			cp -f "/home/nobody/certs/strong/strong.ovpn" "/config/openvpn/openvpn.ovpn"

		else

			echo "[info] VPN default certs defined, copying to /config/openvpn/..."

			# copy default encrption ovpn and certs
			cp -f /home/nobody/certs/default/*.crt /config/openvpn/
			cp -f /home/nobody/certs/default/*.pem /config/openvpn/
			cp -f "/home/nobody/certs/default/default.ovpn" "/config/openvpn/openvpn.ovpn"

		fi

		VPN_CONFIG="/config/openvpn/openvpn.ovpn"

	# if ovpn file not found in /config/openvpn and the provider is not pia then exit
	elif [[ -z "${VPN_CONFIG}" && "${VPN_PROV}" != "pia" ]]; then

		echo "[crit] Missing OpenVPN configuration file in /config/openvpn/ (no files with an ovpn extension exist) please create and then restart this container" && exit 1

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Environment variables defined as follows" ; set
		echo "[debug] Directory listing of files in /config/openvpn as follows" ; ls -al /config/openvpn
		echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
	fi

	echo "[info] VPN config file (ovpn extension) is located at ${VPN_CONFIG}"

	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/bin/dos2unix "${VPN_CONFIG}"

	if [[ "${VPN_PROV}" == "pia" ]]; then
	
		if [[ "${VPN_PROTOCOL}" == "udp" && "${VPN_PORT}" != "1198" && "${STRONG_CERTS}" != "yes" ]]; then
			echo "[warn] VPN provider remote port incorrect, overriding to 1198"
			VPN_PORT="1198"

		elif [[ "${VPN_PROTOCOL}" == "udp" && "${VPN_PORT}" != "1197" && "${STRONG_CERTS}" == "yes" ]]; then
			echo "[warn] VPN provider remote port incorrect, overriding to 1197"
			VPN_PORT="1197"

		
		elif [[ "${VPN_PROTOCOL}" == "tcp" && "${VPN_PORT}" != "502" && "${STRONG_CERTS}" != "yes" ]]; then
			echo "[warn] VPN provider remote port incorrect, overriding to 502"
			VPN_PORT="502"

		
		elif [[ "${VPN_PROTOCOL}" == "tcp" && "${VPN_PORT}" != "501" && "${STRONG_CERTS}" == "yes" ]]; then
			echo "[warn] VPN provider remote port incorrect, overriding to 501"
			VPN_PORT="501"
		fi
	fi

	# if vpn provider not airvpn then write credentials to file (airvpn uses certs for authentication)
	if [[ "${VPN_PROV}" != "airvpn" ]]; then

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

	# remove ping and ping-restart from ovpn file if present, now using flag --keepalive
	if $(grep -Fq "ping" "${VPN_CONFIG}"); then
		sed -i '/ping.*/d' "${VPN_CONFIG}"
	fi

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	if $(grep -Fq "persist-tun" "${VPN_CONFIG}"); then
		sed -i '/persist-tun/d' "${VPN_CONFIG}"
	fi

	# remove reneg-sec from ovpn file if present, this is disabled via command line to prevent re-checks and dropouts
	if $(grep -Fq "reneg-sec" "${VPN_CONFIG}"); then
		sed -i '/reneg-sec.*/d' "${VPN_CONFIG}"
	fi

	# disable proto from ovpn file if present, defined via env variable and passed to openvpn via command line argument
	if $(grep -Fq "proto" "${VPN_CONFIG}"); then
		sed -i -e 's~^proto\s~# Disabled, as we pass this value via env var\n;proto ~g' "${VPN_CONFIG}"
	fi

	# disable remote from ovpn file if present, defined via env variable and passed to openvpn via command line argument
	if $(grep -Fq "remote" "${VPN_CONFIG}"); then
		sed -i -e 's~^remote\s~# Disabled, as we pass this value via env var\n;remote ~g' "${VPN_CONFIG}"
	fi

	# disable dev from ovpn file if present, defined via env variable and passed to openvpn via command line argument
	if $(grep -Fq "dev" "${VPN_CONFIG}"); then
		sed -i -e 's~^dev\s~# Disabled, as we pass this value via env var\n;dev ~g' "${VPN_CONFIG}"
	fi

	# create the tunnel device
	[ -d /dev/net ] || mkdir -p /dev/net
	[ -c /dev/net/"${VPN_DEVICE_TYPE}" ] || mknod /dev/net/"${VPN_DEVICE_TYPE}" c 10 200

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
		name_server_item=$(echo "${name_server_item}" | sed -e 's/^[ \t]*//')

		echo "[info] Adding ${name_server_item} to /etc/resolv.conf"
		echo "nameserver ${name_server_item}" >> /etc/resolv.conf

	done

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Show name servers defined for container" ; cat /etc/resolv.conf
		echo "[debug] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill "${VPN_REMOTE}"
	fi

	# set perms and owner for files in /config/openvpn directory
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	chmod -R 775 "/config/openvpn" &> /dev/null

	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[warn] Unable to chown/chmod /config/openvpn, assuming SMB mountpoint"
	fi

	# setup ip tables and routing for application
	source /root/iptable.sh

	# start openvpn tunnel
	source /root/openvpn.sh

fi
