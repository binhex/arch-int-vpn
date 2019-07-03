#!/bin/bash

# remove previous run output file
rm -f /home/nobody/vpn_incoming_port.txt

# check we are provider pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${VPN_PROV}" == "pia" ]]; then

	if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Port forwarding is not enabled"
		fi

		# create empty incoming port file (read by downloader script)
		touch /home/nobody/vpn_incoming_port.txt

	else

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Port forwarding is enabled"
		fi

		####
		# check endpoint is port forward enabled
		####

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Checking endpoint '${VPN_REMOTE}' is port forward enabled..."
		fi

		# pia api url for endpoint status (port forwarding enabled true|false)
		pia_vpninfo_api="https://www.privateinternetaccess.com/vpninfo/servers?version=82"

		# jq (json query tool) query to select port forward and filter based only on port forward being enabled (true)
		jq_query_filter_portforward='.[] | select(.port_forward|tostring | contains("true"))'

		# remove temp file from previous run
		rm -f "/tmp/pia_vpninfo_api_result"

		# run curly to grab api result
		/root/curly.sh -ct 10 -rc 12 -rw 10 -of "/tmp/pia_vpninfo_api_result" -url "${pia_vpninfo_api}"

		if [[ "${?}" != 0 ]]; then

			echo "[warn] PIA VPN info API currently down, skipping endoint port forwward check"

		else

			# run jq query with the filter
			jq_query_result=$(cat "/tmp/pia_vpninfo_api_result" | jq -r "${jq_query_filter_portforward}" 2> /dev/null)

			# run jq query to get endpoint name (dns) only, use xargs to turn into single line string
			jq_query_details=$(echo "${jq_query_result}" | jq -r '.dns' | xargs)

			# run grep to check that defined vpn remote is in the list of port forward enabled endpoints
			# grep -w = exact match (whole word), grep -q = quiet mode (no output)
			echo "${jq_query_details}" | grep -qw "${VPN_REMOTE}"

			if [[ "${?}" != 0 ]]; then

				echo "[warn] PIA endpoint '${VPN_REMOTE}' is not in the list of endpoints that support port forwarding, DL/UL speeds maybe slow"
				echo "[info] Please consider switching to one of the endpoints shown below"

			else

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] PIA endpoint '${VPN_REMOTE}' is in the list of endpoints that support port forwarding"
				fi

			fi

			# convert to list with separator being space
			IFS=' ' read -ra jq_query_details_list <<< "${jq_query_details}"

			echo "[info] List of PIA endpoints that support port forwarding:-"

			# loop over list of port forward enabled endpooints and echo out to console
			for i in "${jq_query_details_list[@]}"; do
					echo "[info] ${i}"
			done

		fi

		####
		# get dynamically assigned port number
		####

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Attempting to get dynamically assigned port..."
		fi

		# pia api url for getting dynamically assigned port number
		pia_vpnport_api_host="209.222.18.222"
		pia_vpnport_api_port="2000"
		pia_vpnport_api="http://${pia_vpnport_api_host}:${pia_vpnport_api_port}"

		# remove temp file from previous run
		rm -f "/tmp/pia_vpnport_api_result"

		# create pia client id (randomly generated)
		client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

		# run curly to grab api result
		/root/curly.sh -ct 10 -rc 12 -rw 10 -of "/tmp/pia_vpnport_api_result" -url "${pia_vpnport_api}/?client_id=${client_id}"

		if [[ "${?}" != 0 ]]; then

			echo "[warn] PIA VPN port assignment API currently down, terminating OpenVPN process to force retry for incoming port..."
			kill -2 $(cat /root/openvpn.pid)
			exit 1

		else

			VPN_INCOMING_PORT=$(cat /tmp/pia_vpnport_api_result | jq -r '.port')

			if [[ "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Successfully assigned incoming port ${VPN_INCOMING_PORT}"
				fi

				# write port number to text file (read by downloader script)
				echo "${VPN_INCOMING_PORT}" > /home/nobody/vpn_incoming_port.txt

			else

				echo "[warn] PIA VPN assigned port is malformed, terminating OpenVPN process to force retry for incoming port..."
				kill -2 $(cat /root/openvpn.pid)
				exit 1

			fi

		fi

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /home/nobody/vpn_incoming_port.txt

	fi

else

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] VPN provider ${VPN_PROV} is != pia, skipping incoming port assignment"
	fi

fi
