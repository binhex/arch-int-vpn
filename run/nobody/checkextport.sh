#!/bin/bash

if [[ -z "${rtorrent_port}" ]]; then
	echo "[warn] rTorrent port is not defined" ; return 3
fi

# function to check incoming port is open
function check_incoming_port() {

	incoming_port_check_url="${1}"
	regex_open="${2}"
	regex_closed="${3}"

	# make sure external website used to check incoming port is operational
	curly.sh -rc 5 -rw 2 -sm true -url "${incoming_port_check_url}"

	if [[ "${?}" -eq 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Checking rTorrent incoming port '${rtorrent_port}' is open, using external website '${incoming_port_check_url}'..."
		fi

		# use curl to check incoming port is open (web scrape)
		curl --connect-timeout 30 --max-time 120 --silent --data "port=${rtorrent_port}&submit=Check" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_open}" 1> /dev/null

		if [[ "${?}" -eq 0 ]]; then

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] rTorrent incoming port '${rtorrent_port}' is open"

				# mark as port open by returning zero value
				return 0

			fi

		else

			# if port is not open then check we have a match for closed, if no match then suspect web scrape issue
			curl --connect-timeout 30 --max-time 120 --silent --data "port=${rtorrent_port}&submit=Check" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_closed}" 1> /dev/null

			if [[ "${?}" -eq 0 ]]; then

				echo "[info] rTorrent incoming port closed, marking for reconfigure"

				# mark for reconfigure by returning non zero value
				return 1

			else

				echo "[warn] Incoming port site '${incoming_port_check_url}' failed to web scrape, marking as failed"

				# mark as web scrape failed
				return 4

			fi

		fi

	else

		echo "[warn] External site '${incoming_port_check_url}' used to check incoming port is currently down"

		# mark as failure to connect to external site to check port by returning non zero value
		return 2

	fi
}

# run function for first site (web scrape)
check_incoming_port "https://portchecker.co/check" "port ${rtorrent_port} is.*?open" "port ${rtorrent_port} is.*?closed"

# if site down or web scrape error then run function for second site (web scrape)
if [[ "${?}" -eq 2 || "${?}" -eq 4 ]]; then
	check_incoming_port "https://canyouseeme.org/" "success.*?on port.*?${rtorrent_port}" "error.*?on port.*?${rtorrent_port}"
fi
