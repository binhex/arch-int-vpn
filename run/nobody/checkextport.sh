#!/bin/bash

# url to external site used to check incoming port is open
incoming_port_check_url="https://portchecker.co/check"

if [[ -z "${rtorrent_port}" ]]; then
	echo "[warn] rTorrent port is not defined" ; return 3
fi

# make sure external website used to check incoming port is operational
curly.sh -rc 5 -rw 2 -sm true -url "${incoming_port_check_url}"

if [[ "${?}" -eq 0 ]]; then

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking rTorrent incoming port '${rtorrent_port}' is open, using external website '${incoming_port_check_url}'..."
	fi

	# use curl to check incoming port is open (web scrape)
	curl --connect-timeout 30 --max-time 120 --silent --data "port=${rtorrent_port}&submit=Check" -X POST "${incoming_port_check_url}" | grep -i -P "port ${rtorrent_port} is" | grep -i 'open' 1> /dev/null

	if [[ "${?}" -eq 0 ]]; then

		if [[ "${DEBUG}" == "true" ]]; then

			echo "[debug] rTorrent incoming port '${rtorrent_port}' is open"

			# mark as port open by returning zero value
			return 0

		fi

	else

		echo "[info] rTorrent incoming port closed, marking for reconfigure"

		# mark for reconfigure by returning non zero value
		return 1

	fi

else

	echo "[warn] External site '${incoming_port_check_url}' used to check incoming port is currently down"

	# mark as failure to connect to external site to check port by returning non zero value
	return 2

fi
