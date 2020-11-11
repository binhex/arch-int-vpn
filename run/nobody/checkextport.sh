#!/bin/bash

# variable used below with bash indirect expansion
application_incoming_port="${APPLICATION}_port"

if [[ -z "${!application_incoming_port}" ]]; then
	echo "[warn] ${APPLICATION} incoming port is not defined" ; return 3
fi

if [[ -z "${external_ip}" ]]; then
	echo "[warn] External IP address is not defined" ; return 4
fi

# function to check incoming port is open (json)
function check_incoming_port_json() {

	incoming_port_check_url="${1}"
	json_query="${2}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
		set -x
	fi

	response=$(curl --connect-timeout 30 --max-time 120 --silent "${incoming_port_check_url}" | jq "${json_query}")

	if [[ "${response}" == "true" ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		set +x ; return 0

	elif [[ "${response}" == "false" ]]; then

		echo "[info] ${APPLICATION} incoming port '${!application_incoming_port}' is closed, marking for reconfigure"
		set +x ; return 1

	else

		echo "[warn] Incoming port site '${incoming_port_check_url}' failed json download, marking as failed"
		set +x ; return 2

	fi

}

# function to check incoming port is open (webscrape)
function check_incoming_port_webscrape() {

	incoming_port_check_url="${1}"
	post_data="${2}"
	regex_open="${3}"
	regex_closed="${4}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
		set -x
	fi

	# use curl to check incoming port is open (web scrape)
	curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_open}" 1> /dev/null

	if [[ "${?}" -eq 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		set +x ; return 0

	else

		# if port is not open then check we have a match for closed, if no match then suspect web scrape issue
		curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_closed}" 1> /dev/null

		if [[ "${?}" -eq 0 ]]; then

			echo "[info] ${APPLICATION} incoming port closed, marking for reconfigure"
			set +x ; return 1

		else

			echo "[warn] Incoming port site '${incoming_port_check_url}' failed to web scrape, marking as failed"
			set +x ; return 2

		fi

	fi

}

# run function for first site (web scrape)
check_incoming_port_webscrape "https://canyouseeme.org/" "port=${!application_incoming_port}&submit=Check" "success.*?on port.*?${!application_incoming_port}" "error.*?on port.*?${!application_incoming_port}"

# if site down or web scrape error then run function for second site (json)
if [[ "${?}" -eq 2 ]]; then

	check_incoming_port_json "https://ifconfig.co/port/${!application_incoming_port}" ".reachable"

fi

# if port not open or site down then create file to indicate failure which will
# trigger a restart of openvpn by /root/openvpn.sh
if [[ "${?}" -ne 0 ]]; then

	touch "/tmp/portclosed"

fi
