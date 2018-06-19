#!/bin/bash

# define name servers to connect to in order to get external ip address
# if name servers dont respond then use web servers to get external ip address
pri_ns="ns1.google.com"
sec_ns="resolver1.opendns.com"
pri_url="http://checkip.amazonaws.com"
sec_url="http://whatismyip.akamai.com"
ter_url="https://showextip.azurewebsites.net"

# define retry and timeout periods
retry_count=15
sleep_period_secs=2s
curl_connnect_timeout_secs=10
curl_max_time_timeout_secs=30

# remove previous run output file
rm -f /home/nobody/vpn_external_ip.txt

# wait for vpn tunnel to come up before proceeding
source /home/nobody/getvpnip.sh

# function to check ip address is in correct format
check_valid_ip() {

	check_ip="$1"

	# check if the format looks right
	echo "${check_ip}" | egrep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octect is less than or equal to 255
	echo "${check_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	return 0
}

while true; do

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Attempting to get external IP using Name Server '${pri_ns}'..."
	fi

	external_ip="$(dig -b ${vpn_ip} -4 TXT +short o-o.myaddr.l.google.com @${pri_ns} 2> /dev/null | tr -d '"')"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Name Server '${pri_ns}', trying '${sec_ns}'..."
		fi

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		break

	fi

	external_ip="$(dig -b ${vpn_ip} -4 +short myip.opendns.com @${sec_ns} 2> /dev/null)"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary ns
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Name Server '${sec_ns}', trying '${pri_url}'..."
		fi

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		break

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
		break

	fi

	external_ip="$(curl --connect-timeout ${curl_connnect_timeout_secs} --max-time ${curl_max_time_timeout_secs} --interface ${vpn_ip} ${sec_url} 2> /dev/null)"
	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try secondary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Failed to get external IP using Web Server '${sec_url}', trying '${ter_ns}'..."
		fi

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		break

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
		break

	fi

	# if we still havent got the external ip address then sleep and then retry again
	if [ "${retry_count}" -eq "0" ]; then

		external_ip="${vpn_ip}"

		echo "[warn] Cannot determine external IP address, exhausted retries setting to tunnel IP '${external_ip}'"
		break

	else

		retry_count=$((retry_count-1))

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Cannot determine external IP address, retrying..."
		fi

		sleep "${sleep_period_secs}"

	fi

done

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /home/nobody/vpn_external_ip.txt

# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
chmod +r /home/nobody/vpn_external_ip.txt
