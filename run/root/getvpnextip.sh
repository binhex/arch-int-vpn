#!/bin/bash

# ensure we have connectivity before attempting to detect external ip address
source /root/checkvpnconn.sh "google.com" "443"

# define name servers to connect to in order to get external ip address
pri_external_ip_ns="ns1.google.com"
sec_external_ip_ns="resolver1.opendns.com"

# use dns query to get external ip address
external_ip="$(dig TXT +short o-o.myaddr.l.google.com @${pri_external_ip_ns} | tr -d '"')"
exit_code="${?}"

# if error then try secondary name server
if [[ "${exit_code}" != 0 ]]; then

	external_ip="$(dig +short myip.opendns.com @${sec_external_ip_ns})"
	exit_code="${?}"

	if [[ "${exit_code}" != 0 ]]; then

		external_ip="0.0.0.0"

	fi

fi

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /home/nobody/vpn_external_ip.txt
