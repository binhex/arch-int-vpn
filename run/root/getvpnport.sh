#!/bin/bash

# statically assigned url for pia api (taken from pia script)
pia_api_host="209.222.18.222"
pia_api_port="2000"
pia_api_url="http://${pia_api_host}:${pia_api_port}"

# remove previous run output file
rm -f /home/nobody/vpn_incoming_port.txt

# check we are provider pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${VPN_PROV}" == "pia" ]]; then

	# remove temp file from previous run
	rm -f /tmp/VPN_INCOMING_PORT

	# create pia client id (randomly generated)
	client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

	# get an assigned incoming port from pia's api using curl
	curly.sh -rc 12 -rw 10 -of /tmp/VPN_INCOMING_PORT -url "${pia_api_url}/?client_id=${client_id}"
	exit_code=$?

	if [[ "${exit_code}" != 0 ]]; then

		VPN_INCOMING_PORT=""
		echo "[debug] Unable to assign incoming port to current connection"

	else

		VPN_INCOMING_PORT=$(cat /tmp/VPN_INCOMING_PORT | jq -r '.port')

		if [[ "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

			echo "[debug] Successfully assigned incoming port ${VPN_INCOMING_PORT}"

		else

			VPN_INCOMING_PORT=""
			echo "[debug] Incoming port malformed"

		fi

	fi

	# write port number to text file, this is then read by the downloader script
	echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt

else

	echo "[debug] VPN provider ${VPN_PROV} is != pia, skipping incoming port detection"

fi
