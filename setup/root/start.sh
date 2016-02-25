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

	# wildcard search for openvpn config files
	VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print)

	# if vpn provider not set then exit
	if [[ -z "${VPN_PROV}" ]]; then
		echo "[crit] VPN provider not defined, please specify via env variable VPN_PROV" && exit 1
	else
		VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's/^[ \t]*//')
	fi

	echo "[info] VPN provider defined as ${VPN_PROV}"
	
	# if vpn provider is pia and no ovpn then copy
	if [[ -z "${VPN_CONFIG}" && "${VPN_PROV}" == "pia" ]]; then
	
		# copy default certs and ovpn file
		cp -f /home/nobody/ca.crt /config/openvpn/ca.crt
		cp -f /home/nobody/crl.pem /config/openvpn/crl.pem
		cp -f "/home/nobody/openvpn.ovpn" "/config/openvpn/openvpn.ovpn"
		VPN_CONFIG="/config/openvpn/openvpn.ovpn"
		
	# else if not pia and no ovpn then exit
	elif [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] Missing OpenVPN configuration file in /config/openvpn/ (no files with an ovpn extension exist) please create and restart delugevpn" && exit 1
	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Environment variables defined as follows" ; set
	fi
	
	echo "[info] VPN config file (ovpn extension) is located at ${VPN_CONFIG}"
	
	# convert CRLF (windows) to LF (unix) for ovpn
	tr -d '\r' < "${VPN_CONFIG}" > /tmp/convert.ovpn && mv /tmp/convert.ovpn "${VPN_CONFIG}"

	# if vpn remote, port and protocol defined via env vars then use, else use from ovpn
	if [[ ! -z "${VPN_REMOTE}" && ! -z "${VPN_PORT}" && ! -z "${VPN_PROTOCOL}" ]]; then
	
		echo "[info] Env vars defined via docker -e flags for remote host, port and protocol, writing values to ovpn file..."
		
		# strip whitespace from start and end of env vars
		VPN_REMOTE=$(echo "${VPN_REMOTE}" | sed -e 's/^[ \t]*//')
		VPN_PORT=$(echo "${VPN_PORT}" | sed -e 's/^[ \t]*//')
		VPN_PROTOCOL=$(echo "${VPN_PROTOCOL}" | sed -e 's/^[ \t]*//')
		
		# remove proto line from ovpn if present
		sed -i '/proto.*/d' "${VPN_CONFIG}"
		
		# write to ovpn file
		sed -i -e "s/remote\s.*/remote ${VPN_REMOTE} ${VPN_PORT} ${VPN_PROTOCOL}/g" "${VPN_CONFIG}"
		
	else
	
		echo "[info] Env vars not defined for remote host, port and protocol, will parse existing entries from ovpn file..."
		
		# find remote host from ovpn file
		VPN_REMOTE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=remote\s)[^\s]+')
		
		# strip whitespace from start and end of env vars
		VPN_REMOTE=$(echo "${VPN_REMOTE}" | sed -e 's/^[ \t]*//')
		
		# find remote port from ovpn file
		VPN_PORT=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=remote\s).*$' | grep -P -o -m 1 '(?<=\s)[\d]{2,5}(?=[\s])|[\d]{2,5}$')
		
		# strip whitespace from start and end of env vars
		VPN_PORT=$(echo "${VPN_PORT}" | sed -e 's/^[ \t]*//')
		
		# find remote port from ovpn file
		VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=remote\s).*$' | grep -P -o -m 1 'udp|tcp')
		
		if [[ -z "${VPN_PROTOCOL}" ]]; then
			VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=proto\s).*$' | grep -P -o -m 1 'udp|tcp')
		fi
		
		# strip whitespace from start and end of env vars
		VPN_PROTOCOL=$(echo "${VPN_PROTOCOL}" | sed -e 's/^[ \t]*//')
	fi
	
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
	fi

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN provider remote gateway defined as ${VPN_REMOTE}"
	else
		echo "[crit] VPN provider remote gateway not defined, exiting..." && exit 1
	fi
	
	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN provider remote port defined as ${VPN_PORT}"
	else
		echo "[crit] VPN provider remote port not defined, exiting..." && exit 1
	fi
	
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN provider remote protocol defined as ${VPN_PROTOCOL}"
	else
		echo "[crit] VPN provider remote protocol not defined, exiting..." && exit 1
	fi
	
	# if vpn provider not airvpn then write credentials to file
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

	# remove ping and ping-restart from ovpn file if present, now using flag --keepalive
	if $(grep -Fq "ping" "${VPN_CONFIG}"); then
		sed -i '/ping.*/d' "${VPN_CONFIG}"
	fi

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	if $(grep -Fq "persist-tun" "${VPN_CONFIG}"); then
		sed -i '/persist-tun/d' "${VPN_CONFIG}"
	fi

	# create the tunnel device
	[ -d /dev/net ] || mkdir -p /dev/net
	[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

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
