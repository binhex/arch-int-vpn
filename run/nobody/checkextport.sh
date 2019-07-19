#!/bin/bash

# url to external site used to check incoming port is open
incoming_port_check_url="https://portchecker.co/check"

# make sure external website used to check incoming port is operational
exit_code=$(curly.sh -rc 5 -rw 2 -sm true -url "${incoming_port_check_url}")

if [[ "${exit_code}" -eq 0 ]]; then

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking rTorrent incoming port '${rtorrent_port}' is open, using external website '${incoming_port_check_url}'..."
	fi

	# use curl to check incoming port is open
	exit_code=$(curl --connect-timeout 30 --max-time 120 --silent --data "port=${rtorrent_port}&submit=Check" -X POST "${incoming_port_check_url}" | grep -q -i "port ${rtorrent_port} is.*open")

	if [[ "${exit_code}" -ne 0 ]]; then

		echo "[info] rTorrent incoming port closed, marking for reconfigure"

		# mark as reconfigure required due to mismatch
		port_change="true"

	else

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] rTorrent incoming port '${rtorrent_port}' is open"
		fi

	fi

else

	echo "[warn] External site '${incoming_port_check_url}' used to check incoming port is currently down"

fi
