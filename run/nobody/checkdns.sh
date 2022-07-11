#!/bin/bash

# this script checks dns is operational, a file is created if
# dns is not operational and this is monitored and picked up
# by the script /root/openvpn.sh and triggers a restart of the
# openvpn process.

if [[ "${VPN_ENABLED}" == "yes" ]]; then

	if [[ -z "${1}" ]]; then

		echo "[warn] No name argument passed, exiting script '${0}'..."
		exit 1

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking we can resolve name '${1}' to address..."
	fi

	retry_count=12
	retry_wait=5

	while true; do

		retry_count=$((retry_count-1))

		if [ "${retry_count}" -eq "0" ]; then
			echo "[info] DNS failure, creating file '/tmp/dnsfailure' to indicate failure..."
			touch "/tmp/dnsfailure"
			chmod +r "/tmp/dnsfailure"
			break
		fi

		# check we can resolve names before continuing (required for getvpnextip.sh script)
		# note -v 'SERVER' is to prevent name server ip being matched from stdout
		remote_dns_answer=$(drill -a -4 "${1}" 2> /dev/null | grep -v 'SERVER' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)

		# check answer is not blank, if it is blank assume bad ns
		if [[ ! -z "${remote_dns_answer}" ]]; then

			if [[ "${DEBUG}" == "true" ]]; then
				echo "[debug] DNS operational, we can resolve name '${1}' to address '${remote_dns_answer}'"
			fi
			break

		else

			if [[ "${DEBUG}" == "true" ]]; then
				echo "[debug] Having issues resolving name '${1}'"
				echo "[debug] Retrying in ${retry_wait} secs..."
				echo "[debug] ${retry_count} retries left"
			fi
			sleep "${retry_wait}s"

		fi

	done

fi
