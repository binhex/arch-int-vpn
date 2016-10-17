#!/bin/bash

# strip whitespace from start and end of env var
VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's/^[ \t]*//')

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of VPN"

else

	echo "[info] VPN is enabled, beginning configuration of VPN"
	
	# create directory as user root
	mkdir -p /config/openvpn

	# wildcard search for openvpn config files (match on first result)
	VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
	
	# strip whitespace from start and end of env var
	VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's/^[ \t]*//')
	STRONG_CERTS=$(echo "${STRONG_CERTS}" | sed -e 's/^[ \t]*//')

	# if vpn provider not set then exit
	if [[ -z "${VPN_PROV}" ]]; then
		echo "[crit] VPN provider not defined, please specify via env variable VPN_PROV" && exit 1
	fi

	echo "[info] VPN provider defined as ${VPN_PROV}"

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

		echo "[crit] Missing OpenVPN configuration file in /config/openvpn/ (no files with an ovpn extension exist) please create and restart delugevpn" && exit 1

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Environment variables defined as follows" ; set
	fi

	echo "[info] VPN config file (ovpn extension) is located at ${VPN_CONFIG}"

	# convert CRLF (windows) to LF (unix) for ovpn
	tr -d '\r' < "${VPN_CONFIG}" > /tmp/convert.ovpn && mv /tmp/convert.ovpn "${VPN_CONFIG}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Directory listing of files in /config/openvpn as follows" ; ls -al /config/openvpn
	fi

	# use vpn remote, port and protocol defined via env vars
	if [[ ! -z "${VPN_REMOTE}" && ! -z "${VPN_PORT}" && ! -z "${VPN_PROTOCOL}" ]]; then

		echo "[info] Env vars defined via docker -e flags for remote host, port and protocol, writing values to ovpn file..."

		# strip whitespace from start and end of env vars
		VPN_REMOTE=$(echo "${VPN_REMOTE}" | sed -e 's/^[ \t]*//')
		VPN_PORT=$(echo "${VPN_PORT}" | sed -e 's/^[ \t]*//')
		VPN_PROTOCOL=$(echo "${VPN_PROTOCOL}" | sed -e 's/^[ \t]*//')
		VPN_DEVICE_TYPE=$(echo "${VPN_DEVICE_TYPE}" | sed -e 's/^[ \t]*//')
	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
	fi

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN provider remote gateway defined as ${VPN_REMOTE}"
	else
		echo "[crit] VPN provider remote gateway not defined (via -e VPN_REMOTE), exiting..." && exit 1
	fi

	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN provider remote protocol defined as ${VPN_PROTOCOL}"
	else
		echo "[crit] VPN provider remote protocol not defined (via -e VPN_PROTOCOL), exiting..." && exit 1
	fi
	
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		echo "[info] VPN tunnel device type defined as ${VPN_DEVICE_TYPE}"
	else
		echo "[warn] VPN tunnel device not defined (via -e VPN_DEVICE_TYPE), defaulting to 'tun'"
		export VPN_DEVICE_TYPE="tun"
	fi

	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN provider remote port defined as ${VPN_PORT}"
		
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

	else
		echo "[crit] VPN provider remote port not defined (via -e VPN_PORT), exiting..." && exit 1
	fi

	# if vpn provider not airvpn then write credentials to file (airvpn uses certs for authentication)
	if [[ "${VPN_PROV}" != "airvpn" ]]; then

		# store credentials in separate file for authentication
		if ! $(grep -Fq "auth-user-pass credentials.conf" "${VPN_CONFIG}"); then
			sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "${VPN_CONFIG}"
		fi

		# write vpn username to file
		if [[ -z "${VPN_USER}" ]]; then

			echo "[crit] VPN username not specified, please specify using env variable VPN_USER" && exit 1

		else

			# remove whitespace from start and end
			VPN_USER=$(echo "${VPN_USER}" | sed -e 's/^[ \t]*//')
			echo "${VPN_USER}" > /config/openvpn/credentials.conf
		fi

		echo "[info] VPN provider username defined as ${VPN_USER}"

		username_char_check=$(echo "${VPN_USER}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${username_char_check}" ]]; then
			echo "[warn] Username contains characters which could cause authentication issues, please consider changing this if possible"
		fi

		# write vpn password to file
		if [[ -z "${VPN_PASS}" ]]; then

			echo "[crit] VPN password not specified, please specify using env variable VPN_PASS" && exit 1

		else

			# remove whitespace from start and end
			VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's/^[ \t]*//')
			echo "${VPN_PASS}" >> /config/openvpn/credentials.conf
		fi

		echo "[info] VPN provider password defined as ${VPN_PASS}"

		password_char_check=$(echo "${VPN_PASS}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${password_char_check}" ]]; then
			echo "[warn] Password contains characters which could cause authentication issues, please consider changing this if possible"
		fi

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill "${VPN_REMOTE}"
	fi

	# remove ping and ping-restart from ovpn file if present, now using flag --keepalive
	if $(grep -Fq "ping" "${VPN_CONFIG}"); then
		sed -i '/ping.*/d' "${VPN_CONFIG}"
	fi

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	if $(grep -Fq "persist-tun" "${VPN_CONFIG}"); then
		sed -i '/persist-tun/d' "${VPN_CONFIG}"
	fi

	# remove proto from ovpn file if present, defined via env variable and passed to openvpn via command line argument
	if $(grep -Fq "proto" "${VPN_CONFIG}"); then
		sed -i '/proto\s.*/d' "${VPN_CONFIG}"
	fi

	# remove remote from ovpn file if present, defined via env variable and passed to openvpn via command line argument
	if $(grep -Fq "remote" "${VPN_CONFIG}"); then
		sed -i '/remote\s.*/d' "${VPN_CONFIG}"
	fi

	# create the tunnel device
	[ -d /dev/net ] || mkdir -p /dev/net
	[ -c /dev/net/"${VPN_DEVICE_TYPE}" ] || mknod /dev/net/"${VPN_DEVICE_TYPE}" c 10 200

	# get ip for local gateway (eth0)
	DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')
	echo "[info] Default route for container is ${DEFAULT_GATEWAY}"

	# strip whitespace from start and end of env vars (optional)
	ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's/^[ \t]*//')
	LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's/^[ \t]*//')

	# set permissions for /config/openvpn folder
	echo "[info] Setting permissions recursively on /config/openvpn..."
	chown -R "${PUID}":"${PGID}" /config/openvpn
	chmod -R 777 /config/openvpn

	# setup ip tables and routing for application
	source /root/iptable.sh

	# add in google public nameservers (isp may block ns lookup when connected to vpn)
	echo 'nameserver 8.8.8.8' > /etc/resolv.conf
	echo 'nameserver 8.8.4.4' >> /etc/resolv.conf

	echo "[info] nameservers"
	cat /etc/resolv.conf
	echo "--------------------"

	# start openvpn tunnel
	source /root/openvpn.sh

fi
