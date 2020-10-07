#!/bin/bash

if [[ "${VPN_PROV}" == "pia" ]]; then
	if [ -f '/tmp/getvpnport.pid' ]; then
		# kill getvpnport.sh on wireguard down, note use sig 15 not 2
		kill -15 $(cat '/tmp/getvpnport.pid')
	fi
fi
