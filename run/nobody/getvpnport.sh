#!/bin/bash

# check that app requires port forwarding and vpn provider is pia
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]] && [[ "${VPN_PROV}" == "pia" ]]; then

	vpn_port="/tmp/getvpnport"

	if [ ! -f "${vpn_port}" ]; then
		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Waiting for file '${vpn_port}' to be generated (contains PIA API generated incoming port number)..."
		fi
	fi

	while [ ! -f "${vpn_port}" ]
	do
		sleep 1s
	done

	VPN_INCOMING_PORT=$(<"${vpn_port}")

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Incoming port for tunnel is '${VPN_INCOMING_PORT}'"
	fi

fi
