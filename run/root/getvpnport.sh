#!/bin/bash

# statically assigned url for pia api (taken from pia script)
pia_api_host="209.222.18.222"
pia_api_port="2000"
pia_api_url="http://${pia_api_host}:${pia_api_port}"

# remove previous run output file
rm -f /home/nobody/vpn_incoming_port.txt

# wait for vpn tunnel to come up before proceeding
source /home/nobody/getvpnip.sh

# check we are provider pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${VPN_PROV}" == "pia" ]]; then

	if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Port forwarding disabled, skipping incoming port detection"
		fi

		# create empty incoming port file (read by downloader script)
		touch /home/nobody/vpn_incoming_port.txt

	else

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[info] Strict port forwarding enabled, attempting to assign an incoming port..."
		fi

		# remove temp file from previous run
		rm -f /tmp/VPN_INCOMING_PORT

		# create pia client id (randomly generated)
		client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

		# create array of endpoints that support port forwarding (pia only)
		pia_domain_suffix="privateinternetaccess.com"

		pia_port_forward_enabled_endpoints_array=("ca-vancouver.${pia_domain_suffix} (CA Vancouver)" \
		"ca-toronto.${pia_domain_suffix} (CA Toronto)" \
		"ca.${pia_domain_suffix} (CA Montreal)" \
		"czech.${pia_domain_suffix} (Czech Republic)" \
		"spain.${pia_domain_suffix} (Spain)" \
		"swiss.${pia_domain_suffix} (Switzerland)" \
		"sweden.${pia_domain_suffix} (Sweden)" \
		"france.${pia_domain_suffix} (France)" \
		"de-berlin.${pia_domain_suffix} (Germany)" \
		"de-frankfurt.${pia_domain_suffix} (Germany)" \
		"ro.${pia_domain_suffix} (Romania)" \
		"israel.${pia_domain_suffix} (Israel)")

		if [[ ! " ${pia_port_forward_enabled_endpoints_array[@]} " =~ " ${VPN_REMOTE} " ]]; then

			echo "[warn] PIA endpoint '${VPN_REMOTE}' doesn't support port forwarding, DL/UL speeds will be slow"
			echo "[info] Please consider switching to an endpoint that does support port forwarding, shown below:-"
			printf '[info] %s\n' "${pia_port_forward_enabled_endpoints_array[@]}"

			# create empty incoming port file (read by downloader script)
			touch /home/nobody/vpn_incoming_port.txt

		else

			# get an assigned incoming port from pia's api using curl
			/root/curly.sh -rc 12 -rw 10 -of /tmp/VPN_INCOMING_PORT -url "${pia_api_url}/?client_id=${client_id}"
			exit_code=$?

			if [[ "${exit_code}" != 0 ]]; then

				echo "[warn] PIA API currently down, terminating OpenVPN process to force retry for incoming port..."
				kill -2 $(cat /root/openvpn.pid)
				exit 1

			else

				VPN_INCOMING_PORT=$(cat /tmp/VPN_INCOMING_PORT | jq -r '.port')

				if [[ "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

					if [[ "${DEBUG}" == "true" ]]; then
						echo "[debug] Successfully assigned incoming port ${VPN_INCOMING_PORT}"
					fi

					# write port number to text file (read by downloader script)
					echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt

				else

					echo "[warn] PIA incoming port malformed, terminating OpenVPN process to force retry for incoming port..."
					kill -2 $(cat /root/openvpn.pid)
					exit 1

				fi

			fi

		fi

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /home/nobody/vpn_incoming_port.txt

	fi

else

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] VPN provider ${VPN_PROV} is != pia, skipping incoming port detection"
	fi

fi
