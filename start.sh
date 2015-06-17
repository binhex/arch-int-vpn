#!/bin/bash

# create directory
mkdir -p /config/openvpn

# if vpn set to "no" then don't run openvpn
if [[ $VPN_ENABLED == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of OpenVPN"

else

	echo "[info] VPN is enabled, beginning configuration of OpenVPN"

	# wildcard search for openvpn config files
	VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print)

	# if vpn provider not set then exit
	if [[ -z "${VPN_PROV}" ]]; then
		echo "[crit] VPN provider not defined, please specify via env variable VPN_PROV" && exit 1

	# if airvpn vpn provider chosen then do NOT copy base config file
	elif [[ $VPN_PROV == "airvpn" ]]; then

		echo "[info] VPN provider defined as $VPN_PROV"
		if [[ -z "${VPN_CONFIG}" ]]; then
			echo "[crit] VPN provider defined as $VPN_PROV, no files with an ovpn extension exist in /config/openvpn/ please create and restart delugevpn" && exit 1
		fi

	# if pia vpn provider chosen then copy base config file and pia certs
	elif [[ $VPN_PROV == "pia" ]]; then

		# copy default certs
		echo "[info] VPN provider defined as $VPN_PROV"
		cp -f /home/nobody/ca.crt /config/openvpn/ca.crt
		cp -f /home/nobody/crl.pem /config/openvpn/crl.pem

		# if no ovpn files exist then copy base file
		if [[ -z "${VPN_CONFIG}" ]]; then
			cp -f "/home/nobody/openvpn.ovpn" "/config/openvpn/openvpn.ovpn"
			VPN_CONFIG="/config/openvpn/openvpn.ovpn"
		fi

		# if no remote gateway or port specified then use netherlands and default port
		if [[ -z "${VPN_REMOTE}" && -z "${VPN_PORT}" ]]; then
			echo "[warn] VPN remote gateway and port not defined, defaulting to netherlands port 1194"
			sed -i -e "s/remote\s.*/remote nl.privateinternetaccess.com 1194/g" "$VPN_CONFIG"

		# if no remote gateway but port defined then use netherlands and defined port
		elif [[ -z "${VPN_REMOTE}" && ! -z "${VPN_PORT}" ]]; then
			echo "[warn] VPN remote gateway not defined and port defined, defaulting to netherlands"
			sed -i -e "s/remote\s.*/remote nl.privateinternetaccess.com $VPN_PORT/g" "$VPN_CONFIG"

		# if remote gateway defined but port not defined then use default port
		elif [[ ! -z "${VPN_REMOTE}" && -z "${VPN_PORT}" ]]; then
			echo "[warn] VPN remote gateway defined but no port defined, defaulting to port 1194"
			sed -i -e "s/remote\s.*/remote $VPN_REMOTE 1194/g" "$VPN_CONFIG"

		# if remote gateway and port defined then use both
		else
			echo "[info] VPN provider remote and port defined as $VPN_REMOTE $VPN_PORT"
			sed -i -e "s/remote\s.*/remote $VPN_REMOTE $VPN_PORT/g" "$VPN_CONFIG"
		fi

		# store credentials in separate file for authentication
		if ! $(grep -Fq "auth-user-pass credentials.conf" "$VPN_CONFIG"); then
			sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "$VPN_CONFIG"
		fi

		# write vpn username to file
		if [[ -z "${VPN_USER}" ]]; then
			echo "[crit] VPN username not specified" && exit 1
		else
			echo "${VPN_USER}" > /config/openvpn/credentials.conf
		fi

		# append vpn password to file
		if [[ -z "${VPN_PASS}" ]]; then
			echo "[crit] VPN password not specified" && exit 1
		else
			echo "${VPN_PASS}" >> /config/openvpn/credentials.conf
		fi

	# if custom vpn provider chosen then do NOT copy base config file
	elif [[ $VPN_PROV == "custom" ]]; then

		echo "[info] VPN provider defined as $VPN_PROV"
		if [[ -z "${VPN_CONFIG}" ]]; then
			echo "[crit] VPN provider defined as $VPN_PROV, no files with an ovpn extension exist in /config/openvpn/ please create and restart delugevpn" && exit 1
		fi

		# store credentials in separate file for authentication
		if ! $(grep -Fq "auth-user-pass credentials.conf" "$VPN_CONFIG"); then
			sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "$VPN_CONFIG"
		fi

		# write vpn username to file
		if [[ -z "${VPN_USER}" ]]; then
			echo "[crit] VPN username not specified" && exit 1
		else
			echo "${VPN_USER}" > /config/openvpn/credentials.conf
		fi

		# append vpn password to file
		if [[ -z "${VPN_PASS}" ]]; then
			echo "[crit] VPN password not specified" && exit 1
		else
			echo "${VPN_PASS}" >> /config/openvpn/credentials.conf
		fi

	# if provider none of the above then exit
	else
		echo "[crit] VPN provider unknown, please specify airvpn, pia, or custom" && exit 1
	fi

	# customise ovpn file to ping tunnel every 5 mins
	if ! $(grep -Fxq "ping 300" "$VPN_CONFIG"); then
		sed -i '/remote\s.*/a ping 300' "$VPN_CONFIG"
	fi

	# customise ovpn file to restart tunnel after 10 mins if no reply from ping (twice)
	if ! $(grep -Fxq "ping-restart 600" "$VPN_CONFIG"); then
		sed -i '/ping 300/a ping-restart 600' "$VPN_CONFIG"
	fi

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	if $(grep -Fq "persist-tun" "$VPN_CONFIG"); then
		sed -i '/persist-tun/d' "$VPN_CONFIG"
	fi

	# read port number and protocol from ovpn file (used to define iptables rule)
	VPN_PORT=$(cat "$VPN_CONFIG" | grep -P -o -m 1 '^remote\s[^\r\n]+' | grep -P -o -m 1 '[\d]+$')
	VPN_PROTOCOL=$(cat "$VPN_CONFIG" | grep -P -o -m 1 '(?<=proto\s)[^\r\n]+')

	# set permissions to user nobody
	chown -R nobody:users /config/openvpn
	chmod -R 775 /config/openvpn

	# create the tunnel device
	[ -d /dev/net ] || mkdir -p /dev/net
	[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

	# get ip for local gateway (eth0)
	DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')

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
