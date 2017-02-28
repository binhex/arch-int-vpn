#!/bin/bash

# ensure we have connectivity before attempting to assign incoming port from pia api
source /root/checkvpnconn.sh

# statically assigned url for pia api (taken from their script)
pia_api_url="http://209.222.18.222:2000"

# create pia client id (randomly generated)
client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

# get an assigned incoming port from pia's api using curl
VPN_INCOMING_PORT=$(curl --connect-timeout 5 --max-time 10 --retry 6 --retry-max-time 60 -s "${pia_api_url}/?client_id=${client_id}" | jq -r '.port')

if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then
	VPN_INCOMING_PORT=""
fi

# write port number to text file, this is then read by the downloader script
echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt
