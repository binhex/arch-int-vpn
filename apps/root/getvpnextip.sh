#!/bin/bash

# ensure we have connectivity before attempting to detect external ip address
source /root/checkvpnconn.sh

# define name servers to connect to in order to get external ip address
pri_external_ip_ns="ns1.google.com"
sec_external_ip_ns="resolver1.opendns.com"

# use dns query to get external ip address
external_ip="$(dig TXT +short o-o.myaddr.l.google.com @${pri_external_ip_ns} | tr -d '"')"
check_valid_ip "${external_ip}"
exit_code="${?}"

# if error then try secondary name server
if [[ "${exit_code}" != 0 ]]; then

	echo "[warn] Cannot determine external IP address from '${pri_external_ip_ns}', trying alternative name server..."

	external_ip="$(dig +short myip.opendns.com @${sec_external_ip_ns})"
	check_valid_ip "${external_ip}"
	exit_code="${?}"

	if [[ "${exit_code}" != 0 ]]; then

		echo "[warn] Cannot determine external IP address from '${sec_external_ip_ns}', possible connection issues at present."

		external_ip="0.0.0.0"
		return 1

	fi

fi

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] External IP address from tunnel is '${external_ip}'"
fi

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /home/nobody/vpn_external_ip.txt
