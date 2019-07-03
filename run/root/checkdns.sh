#!/bin/bash

if [[ "${VPN_ENABLED}" == "yes" ]]; then

	if [[ -z "${1}" ]]; then

		echo "[warn] No name argument passed, exiting script '${0}'..."
		exit 1

	fi

	echo "[info] Checking we can resolve name '${1}' to address..."

	while true; do

		# check we can resolve names before continuing (required for getvpnextip.sh script)
		# note -v 'SERVER' is to prevent name server ip being matched from stdout
		remote_dns_answer=$(drill -4 "${1}" | grep -v 'SERVER' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)

		# check answer is not blank, if it is blank assume bad ns
		if [[ ! -z "${remote_dns_answer}" ]]; then

			echo "[info] DNS operational, we can resolve name '${1}' to address '${remote_dns_answer}'"
			break

		else

			if [[ "${DEBUG}" == "true" ]]; then
				echo "[debug] Having issues resolving name '${1}', sleeping before retry..."
				sleep 5s
			fi

		fi

	done

fi
