#!/bin/bash

# check we have internet connectivity before we attempt to use curl to get vpn incoming port
check_site_hostname="ns1.google.com"
check_site_port=53
counter=0

echo "[info] Checking we have Internet connectivity..."

while ! nc -z -w 1 "${check_site_hostname}" "${check_site_port}"; do
  if [[ "${DEBUG}" == "true" ]]; then
    echo "[debug] Cannot connect to hostname ${check_site_hostnme} port ${check_site_port}, retrying..."
  fi
  counter=$((counter+1))
  if (( ${counter} > 9 )); then
    echo "[warn] Cannot detect Internet connectivity, giving up"
    break
  fi
done
