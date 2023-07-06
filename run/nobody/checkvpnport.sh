#!/bin/bash

# check that app requires port forwarding and vpn provider is pia
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]] && [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]]; then

	vpn_port="/tmp/getvpnport"

	while [ ! -f "${vpn_port}" ]
	do
		sleep 1s
	done

	VPN_INCOMING_PORT=$(<"${vpn_port}")

fi
