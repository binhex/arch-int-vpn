#!/bin/bash

# define name servers to connect to in order to get external ip address
pri_external_ip_ns="ns1.google.com"
sec_external_ip_ns="resolver1.opendns.com"
retry_count=30

# remove previous run output file
rm -f /home/nobody/vpn_external_ip.txt

# wait for vpn tunnel to come up before proceeding
source /home/nobody/getvpnip.sh

while true; do

	external_ip="$(dig TXT +short o-o.myaddr.l.google.com @${pri_external_ip_ns} | tr -d '"')"
	exit_code="${?}"

	# if error then try secondary name server
	if [[ "${exit_code}" != 0 ]]; then

		echo "[warn] Failed to get external IP from Google NS, trying OpenDNS..."

		external_ip="$(dig +short myip.opendns.com @${sec_external_ip_ns})"
		exit_code="${?}"

		if [[ "${exit_code}" != 0 ]]; then

			if [ "${retry_count}" -eq "0" ]; then

				external_ip="0.0.0.0"

				echo "[warn] Cannot determine external IP address, exausted retries setting to ${external_ip}"
				break

			else

				retry_count=$((retry_count-1))
				sleep 1s

			fi

		else

			echo "[info] Successfully retrieved external IP address ${external_ip}"
			break

		fi

	else

		echo "[info] Successfully retrieved external IP address ${external_ip}"
		break

	fi

done

# write external ip address to text file, this is then read by the downloader script
echo "${external_ip}" > /home/nobody/vpn_external_ip.txt

# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
chmod +r /home/nobody/vpn_external_ip.txt
