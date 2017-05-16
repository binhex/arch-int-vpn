#!/bin/bash

# check we are provider pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${VPN_PROV}" == "pia" ]]; then

	# ensure we have connectivity before attempting to assign incoming port from pia api
	source /root/checkvpnconn.sh "google.com" "443"

	# statically assigned url for pia api (taken from pia script)
	pia_api_host="209.222.18.222"
	pia_api_port="2000"
	pia_api_url="http://${pia_api_host}:${pia_api_port}"

	# ugly hack to wait until pia api is properly accessible (cnanot find a way to identify this state at the moment)
	sleep 5s

	# create pia client id (randomly generated)
	client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

	# get an assigned incoming port from pia's api using curl
	VPN_INCOMING_PORT=$(curl --connect-timeout 5 --max-time 10 --retry 6 --retry-max-time 60 -s "${pia_api_url}/?client_id=${client_id}" | jq -r '.port')

	if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

		VPN_INCOMING_PORT=""
		echo "[debug] Unable to assign incoming port to current connection"

	else

		echo "[debug] Successfully assigned incoming port ${VPN_INCOMING_PORT}"
	fi

	# write port number to text file, this is then read by the downloader script
	echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt

else

	echo "[debug] VPN provider ${VPN_PROV} is != pia, skipping incoming port detection"

fi
