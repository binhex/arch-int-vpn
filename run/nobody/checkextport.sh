#!/bin/bash

# variable used below with bash indirect expansion
application_incoming_port="${APPLICATION}_port"

if [[ -z "${!application_incoming_port}" ]]; then
	echo "[warn] ${APPLICATION} incoming port is not defined" ; return 3
fi

if [[ -z "${external_ip}" ]]; then
	echo "[warn] External IP address is not defined" ; return 4
fi

# function to check incoming port is open
function check_incoming_port() {

	incoming_port_check_url="${1}"
	post_data="${2}"
	regex_open="${3}"
	regex_closed="${4}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external website '${incoming_port_check_url}'..."
		set -x
	fi

	# make sure external website used to check incoming port is operational
	curly.sh --retry-count 5 --retry-wait 2 --no-progress "true" --no-output "true" -url "${incoming_port_check_url}"

	if [[ "${?}" -eq 0 ]]; then

		# use curl to check incoming port is open (web scrape)
		curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_open}" 1> /dev/null

		if [[ "${?}" -eq 0 ]]; then

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"

				# mark as port open by returning zero value and setting variable
				set +x ; return 0

			fi

		else

			# if port is not open then check we have a match for closed, if no match then suspect web scrape issue
			curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_closed}" 1> /dev/null

			if [[ "${?}" -eq 0 ]]; then

				echo "[info] ${APPLICATION} incoming port closed, marking for reconfigure"

				# mark for reconfigure by returning non zero value and setting variable
				set +x ; return 1

			else

				echo "[warn] Incoming port site '${incoming_port_check_url}' failed to web scrape, marking as failed"

				# mark as web scrape failed
				set +x ; return 4

			fi

		fi

	else

		echo "[warn] External site '${incoming_port_check_url}' used to check incoming port is currently down"

		# mark as failure to connect to external site to check port by returning non zero value
		set +x ; return 2

	fi
}

# run function for first site (web scrape)
check_incoming_port "https://portchecker.co/" "target_ip=${external_ip}&port=${!application_incoming_port}" "Port ${!application_incoming_port} is.*?open" "Port ${!application_incoming_port} is.*?closed"

# if site down or web scrape error then run function for second site (web scrape)
if [[ "${?}" -eq 2 || "${?}" -eq 4 ]]; then

	check_incoming_port "https://canyouseeme.org/" "port=${!application_incoming_port}&submit=Check" "success.*?on port.*?${!application_incoming_port}" "error.*?on port.*?${!application_incoming_port}"

fi

# if port not open or site down then create file to indicate failure which will
# trigger a restart of openvpn by /root/openvpn.sh
if [[ "${?}" -ne 0 ]]; then

	touch "/tmp/portclosed"

fi
