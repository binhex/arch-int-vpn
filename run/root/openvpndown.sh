#!/bin/bash

if [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]]; then
	if [ -f '/tmp/getvpnport.pid' ]; then
		# kill tools.sh/get_vpn_incoming_port on openvpn down, note use sig 15 not 2
		kill -15 $(cat '/tmp/getvpnport.pid') 2> /dev/null
		rm -f '/tmp/getvpnport.pid'
	fi
fi

# create file that denotes tunnel as down to prevent dns resolution check
touch '/tmp/tunneldown' && chmod +r '/tmp/tunneldown'
