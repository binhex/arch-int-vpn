#!/bin/bash

# check we have internet connectivity before we attempt to use curl to get vpn incoming port
check_site_hostname="ns1.google.com"
check_site_port=53
counter=0

echo "[debug] Checking Internet connectivity..."

while ! nc -z -w 1 "${check_site_hostname}" "${check_site_port}"; do

	counter=$((counter+1))
	if (( ${counter} > 9 )); then
		echo "[debug] Cannot detect Internet connectivity, giving up"
		return 1
	else
		echo "[debug] Cannot connect to hostname '${check_site_hostname}' port '${check_site_port}', retrying..."
	fi

done

echo "[debug] Successfully connected to hostname '${check_site_hostname}' port '${check_site_port}'"
