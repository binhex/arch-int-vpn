#!/bin/bash

vpn_port="/home/nobody/vpn_incoming_port.txt"

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
