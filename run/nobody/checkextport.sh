#!/bin/bash

# variable used below with bash indirect expansion
application_incoming_port="${APPLICATION}_port"

if [[ -z "${!application_incoming_port}" ]]; then
	echo "[warn] ${APPLICATION} incoming port is not defined" ; return 3
fi

if [[ -z "${external_ip}" ]]; then
	echo "[warn] External IP address is not defined" ; return 4
fi

# function to check incoming port is open (webscrape)
function check_incoming_port_webscrape() {

	incoming_port_check_url="${1}"
	post_data="${2}"
	regex_open="${3}"
	regex_closed="${4}"

	site_up="false"
	port_open="false"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
	fi

	# use curl to check incoming port is open (web scrape)
	if curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_open}" 1> /dev/null; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		site_up="true"
		port_open="true"
		return

	else

		# if port is not open then check we have a match for closed, if no match then suspect web scrape issue
		if curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_closed}" 1> /dev/null; then

			echo "[info] ${APPLICATION} incoming port closed, marking for reconfigure"
			site_up="true"
			return

		else

			echo "[warn] Incoming port site '${incoming_port_check_url}' failed to web scrape, marking as failed"
			return

		fi

	fi

}

# function to check incoming port is open (json)
function check_incoming_port_json() {

	incoming_port_check_url="${1}"
	json_query="${2}"

	site_up="false"
	port_open="false"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
	fi

	response=$(curl --connect-timeout 30 --max-time 120 --silent "${incoming_port_check_url}" | jq "${json_query}")

	if [[ "${response}" == "true" ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		site_up="true"
		port_open="true"
		return

	elif [[ "${response}" == "false" ]]; then

		echo "[info] ${APPLICATION} incoming port '${!application_incoming_port}' is closed, marking for reconfigure"
		site_up="true"
		return

	else

		echo "[warn] Incoming port site '${incoming_port_check_url}' failed json download, marking as failed"
		return

	fi

}

# run function for first site (web scrape)
check_incoming_port_webscrape "https://canyouseeme.org/" "port=${!application_incoming_port}&submit=Check" "success.*?on port.*?${!application_incoming_port}" "error.*?on port.*?${!application_incoming_port}"

# if web scrape error/site down then try second site (json)
if [[ "${site_up}" == "false" ]]; then
	check_incoming_port_json "https://ifconfig.co/port/${!application_incoming_port}" ".reachable"
fi

# if port down then mark as closed
if [[ "${port_open}" == "false" ]]; then
	touch "/tmp/portclosed"
	return
fi
