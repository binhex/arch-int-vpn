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

# remove previous run output file
rm -f /home/nobody/vpn_external_ip.txt

# wait for vpn tunnel to come up before proceeding
source /home/nobody/getvpnip.sh

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

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Attempting to get external IP using Name Server '${pri_ns}'..."
	fi

	# note -v 'SERVER' is to prevent name server ip being matched from stdout
	external_ip="$(drill -I ${vpn_ip} -4 TXT o-o.myaddr.l.google.com @${pri_ns} | grep -v 'SERVER' | grep -oP '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Name Server '${pri_ns}', trying '${sec_ns}'..."
		fi

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

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Name Server '${sec_ns}', trying '${pri_url}'..."
		fi

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

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Web Server '${pri_url}', trying '${sec_url}'..."
		fi

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

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Web Server '${sec_url}', trying '${ter_url}'..."
		fi

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

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Web Server '${ter_url}'"
		fi

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		eval "$1=${external_ip}"
		return 0

	fi

	# if we still havent got the external ip address then set to loopback and exit
	echo "[warn] Cannot determine external IP address, exhausted retries setting to lo '127.0.0.1'"
	eval "$1=127.0.0.1"
	return 1

}

# save return value from function
external_ip=""
get_external_ip external_ip

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /home/nobody/vpn_external_ip.txt

# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
chmod +r /home/nobody/vpn_external_ip.txt
