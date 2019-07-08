#!/bin/bash

# define name servers to connect to in order to get external ip address
# if name servers dont respond then use web servers to get external ip address
pri_ns="ns1.google.com"
sec_ns="resolver1.opendns.com"
pri_url="http://checkip.amazonaws.com"
sec_url="http://whatismyip.akamai.com"
ter_url="https://showextip.azurewebsites.net"

# define timeout periods
curl_connnect_timeout_secs=10
curl_max_time_timeout_secs=30

# function to check ip address is in correct format
function check_valid_ip() {

	check_ip="$1"

	# check if the format looks right
	echo "${check_ip}" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octect is less than or equal to 255
	echo "${check_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	return 0
}

# function to attempt to get external ip using ns or web
function get_external_ip() {

	echo "[info] Attempting to get external IP using Name Server '${pri_ns}'..."

	# note -v 'SERVER' is to prevent name server ip being matched from stdout
	external_ip="$(drill -I ${vpn_ip} -4 TXT o-o.myaddr.l.google.com @${pri_ns} | grep -v 'SERVER' | grep -oP '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP using Name Server '${pri_ns}', trying '${sec_ns}'..."

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	# note -v 'SERVER' is to prevent name server ip being matched from stdout
	external_ip="$(drill -I ${vpn_ip} -4 myip.opendns.com @${sec_ns} | grep -v 'SERVER' | grep -oP '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP using Name Server '${sec_ns}', trying '${pri_url}'..."

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${pri_url} 2> /dev/null)"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try primary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP using Web Server '${pri_url}', trying '${sec_url}'..."

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${sec_url} 2> /dev/null)"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP using Web Server '${sec_url}', trying '${ter_url}'..."

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${ter_url} 2> /dev/null | grep -P -o -m 1 '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP using Web Server '${ter_url}'"

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	# if we still havent got the external ip address then perform tests and then set to loopback and exit
	echo "[warn] Cannot determine external IP address, performing tests before setting to lo '127.0.0.1'..."
	echo "[info] Show name servers defined for container" ; cat /etc/resolv.conf
	echo "[info] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill -I ${vpn_ip} -4 "${VPN_REMOTE}"
	echo "[info] Show contents of hosts file" ; cat /etc/hosts
	eval "$1=127.0.0.1"
	return 1

}

# save return value from function
external_ip=""
get_external_ip external_ip

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /tmp/getvpnextip

# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
chmod +r /tmp/getvpnextip
