#!/bin/bash

if [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]]; then
	if [ -f '/tmp/getvpnport.pid' ]; then
		# kill getvpnport.sh on openvpn down, note use sig 15 not 2
		kill -15 $(cat '/tmp/getvpnport.pid') 2> /dev/null
		rm -f '/tmp/getvpnport.pid'
	fi
fi
