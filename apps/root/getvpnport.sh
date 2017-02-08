#!/bin/bash

# statically assigned url for pia api (taken from their script)
pia_api_url="http://209.222.18.222:2000"

# get an assigned incoming port from pia's api using curl
echo "[info] Attempting connection to PIA in order to assign a port forward for this session..."
VPN_INCOMING_PORT=$(curl --connect-timeout 10 --max-time 20 --retry 6 --retry-max-time 120 -s "${pia_api_url}/?client_id=$client_id" | jq -r '.port')

if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then
  echo "[warn] Port forwarding is already activated on this connection, has expired, or you are NOT connected to a PIA region that supports port forwarding"
  VPN_INCOMING_PORT=""
fi

# write port number to text file, this is then read by the downloader script
echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt
