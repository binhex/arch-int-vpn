#!/bin/bash

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

# function to get external ip using name server lookup
function get_external_ip_ns() {

	ns_query="${1}"
	site="${2}"

	# note -v 'SERVER' is to prevent name server ip being matched from stdout
	external_ip="$(drill -a -I ${vpn_ip} -4 ${ns_query} ${site} | grep -v 'SERVER' | grep -m 63 -oP '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "1"

	else

		# write external ip address to text file, this is then read by the downloader script
		echo "${external_ip}" > /tmp/getvpnextip

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /tmp/getvpnextip

		echo "${external_ip}"

	fi

}

# function to get external ip using website lookup
function get_external_ip_web() {

	site="${1}"
	grep_regex="${2}"

	if [[ -n "${grep_regex}" ]];then
		external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${site} 2> /dev/null | grep -P -o -m 1 ${grep_regex})"
	else
		external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${site} 2> /dev/null)"
	fi

	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try primary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "1"

	else

		# write external ip address to text file, this is then read by the downloader script
		echo "${external_ip}" > /tmp/getvpnextip

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /tmp/getvpnextip

		echo "${external_ip}"

	fi

}

# check that app requires external ip (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]]; then

	if [[ -z "${vpn_ip}" ]]; then
		echo "[warn] VPN IP address is not defined or is an empty string"
		return 1
	fi

	site="ns1.google.com"
	ns_query="TXT o-o.myaddr.l.google.com"

	echo "[info] Attempting to get external IP using Name Server '${site}'..."
	result=$(get_external_ip_ns "${ns_query}" "@${site}")

	if [ "${result}" == "1" ]; then

		site="resolver1.opendns.com"
		ns_query="myip.opendns.com"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_ns "${ns_query}" "@${site}")

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

	if [ "${result}" == "1" ]; then

		site="http://checkip.amazonaws.com"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}")

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

	if [ "${result}" == "1" ]; then

		site="http://whatismyip.akamai.com"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}")

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

	if [ "${result}" == "1" ]; then

		site="https://showextip.azurewebsites.net"
		grep_regex='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}" "${grep_regex}")

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

	if [ "${result}" == "1" ]; then

		echo "[warn] Cannot determine external IP address, performing tests before setting to '127.0.0.1'..."
		echo "[info] Show name servers defined for container" ; cat /etc/resolv.conf
		echo "[info] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill -a -I ${vpn_ip} -4 "${VPN_REMOTE}"
		echo "[info] Show contents of hosts file" ; cat /etc/hosts

		# write external ip address to text file, this is then read by the downloader script
		echo "127.0.0.1" > /tmp/getvpnextip

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /tmp/getvpnextip

		return 1

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

else

	echo "[info] Application does not require external IP address, skipping external IP address detection"

fi
