#!/bin/bash

# check endpoint is port forward enabled (pia only)
function port_forward_status() {

	echo "[info] Port forwarding is enabled"

	echo "[info] Checking endpoint '${vpn_remote_server}' is port forward enabled..."

	# run curl to grab api result
	jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

	if [[ "${?}" != 0 ]]; then

		echo "[warn] PIA VPN info API currently down, skipping endpoint port forward check"

	else

		# run jq query to get endpoint name (dns) only, use xargs to turn into single line string
		jq_query_details=$(echo "${jq_query_result}" | jq -r "${jq_query_portforward_enabled}" 2> /dev/null | xargs)

		# run grep to check that defined vpn remote is in the list of port forward enabled endpoints
		# grep -w = exact match (whole word), grep -q = quiet mode (no output)
		echo "${jq_query_details}" | grep -qw "${vpn_remote_server}"

		if [[ "${?}" != 0 ]]; then

			echo "[warn] PIA endpoint '${vpn_remote_server}' is not in the list of endpoints that support port forwarding, DL/UL speeds maybe slow"
			echo "[info] Please consider switching to one of the endpoints shown below"

		else

			echo "[info] PIA endpoint '${vpn_remote_server}' is in the list of endpoints that support port forwarding"

		fi

		# convert to list with separator being space
		IFS=' ' read -ra jq_query_details_list <<< "${jq_query_details}"

		echo "[info] List of PIA endpoints that support port forwarding:-"

		# loop over list of port forward enabled endpooints and echo out to console
		for i in "${jq_query_details_list[@]}"; do
				echo "[info] ${i}"
		done

	fi

}

# attempt to get incoming port (pia only)
function get_incoming_port_legacy() {

	echo "[info] Attempting to get dynamically assigned port..."

	# pia api url for getting dynamically assigned port number
	pia_vpnport_api_host="209.222.18.222"
	pia_vpnport_api_port="2000"
	pia_vpnport_api="http://${pia_vpnport_api_host}:${pia_vpnport_api_port}"

	# create pia client id (randomly generated)
	client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")

	# run curly to grab api result
	pia_vpnport_api_result=$(curl --silent --insecure "${pia_vpnport_api}/?client_id=${client_id}")

	if [[ "${?}" != 0 ]]; then

		echo "[warn] PIA VPN port assignment API currently down, terminating OpenVPN process to force retry for incoming port..."
		kill -2 $(cat /root/openvpn.pid)
		return 1

	else

		VPN_INCOMING_PORT=$(echo "${pia_vpnport_api_result}" | jq -r '.port')

		if [[ "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

			echo "[info] Successfully assigned incoming port ${VPN_INCOMING_PORT}"

			# write port number to text file (read by downloader script)
			echo "${VPN_INCOMING_PORT}" > /tmp/getvpnport

		else

			kill_openvpn

		fi

	fi

	# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
	chmod +r /tmp/getvpnport

}

# attempt to get incoming port (pia only)
function get_incoming_port_nextgen() {

	retry_count=12
	retry_wait_secs=10

	while true; do

		# get vpn local ip (not used) and gateway ip
		source /root/getvpnip.sh

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				kill_openvpn

			fi

			# note use of 10.0.0.1 is only AFTER vpn is established, otherwise you need to get the meta ip using the code below:-

			# <snip>
			# download json data
			#jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

			# get metadata server ip address
			#vpn_remote_metadata_server_ip=$(echo "${jq_query_result}" | jq -r "${jq_query_metadata_ip}")

			# get token json response BEFORE vpn established
			#token_json_response=$(curl --silent --insecure -u "${VPN_USER}:${VPN_PASS}" "https://${vpn_remote_metadata_server_ip}/authv3/generateToken")
			# </snip>

			# get token json response AFTER vpn established
			token_json_response=$(curl --silent --insecure -u "${VPN_USER}:${VPN_PASS}" "https://10.0.0.1/authv3/generateToken")

			if [ "$(echo "${token_json_response}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json to generate token from URL 'https://10.0.0.1/authv3/generateToken'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s

			else

				# reset retry count on successful step
				retry_count=12
				break

			fi

		done

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				kill_openvpn

			fi

			# get token
			token=$(echo "${token_json_response}" | jq -r '.token')

			# get payload and signature
			# note use of urlencode, this is required, otherwise login failure can occur
			payload_and_sig=$(curl --insecure --silent --max-time 5 --get --data-urlencode "token=${token}" "https://${vpn_gateway_ip}:19999/getSignature")

			if [ "$(echo "${payload_and_sig}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json payload from URL 'https://${vpn_gateway_ip}:19999/getSignature?token=${token}'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s

			else

				# reset retry count on successful step
				retry_count=12
				break

			fi

		done

		payload=$(echo "${payload_and_sig}" | jq -r '.payload')
		signature=$(echo "${payload_and_sig}" | jq -r '.signature')

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				kill_openvpn

			fi

			# decode payload to get token, port, and expires date (2 months)
			payload_decoded=$(echo "${payload}" | base64 -d | jq)

			if [ "${?}" -ne 0 ]; then

				echo "[warn] Unable to decode payload '${payload}'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s

			else

				# reset retry count on successful step
				retry_count=12
				break

			fi

		done

		token=$(echo "${payload_decoded}" | jq -r '.token')
		port=$(echo "${payload_decoded}" | jq -r '.port')
		# note expires_at time in this format'2020-11-24T22:12:07.627551124Z'
		expires_at=$(echo "${payload_decoded}" | jq -r '.expires_at')

		if [[ "${DEBUG}" == "true" ]]; then

			echo "[debug] Token is '${token}'"
			echo "[debug] Port allocated is '${port}'"
			echo "[debug] Port expires at '${expires_at}'"

		fi

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				kill_openvpn

			fi

			if [[ "${port}" =~ ^-?[0-9]+$ ]]; then

				# write port number to text file (read by downloader script)
				echo "${port}" > /tmp/getvpnport

				# reset retry count on successful step
				retry_count=12
				break

			else

				echo "[warn] Unable to decode payload '${payload}'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s

			fi

		done

		# run function to bind port every 15 minutes (background)
		bind_incoming_port_nextgen &

		# current time in GMT minus 2 hours to ensure we are within the 2 month time period, compared to epoch
		current_datetime_epoch=$(TZ=GMT date -d '2 hour ago' +%s)

		# expires_at datetime as a date object in current time format, compared to epoch
		expires_at_convert_epoch=$(date -d "${expires_at}" +%s)

		# calculate time left before port expires
		expires_at_delta=$(( (expires_at_convert_epoch - current_datetime_epoch) ))

		# sleep for time difference
		sleep "${expires_at_delta}"s

	done

}

# attempt to bind incoming port (pia only)
function bind_incoming_port_nextgen() {

	retry_count=12
	retry_wait_secs=10

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Attempting to bind port failed, kill openvpn process to force retry of incoming port"
			kill -2 $(cat /root/openvpn.pid)
			return 1

		fi

		# note use of urlencode, this is required, otherwise login failure can occur
		bind_port=$(curl --insecure --silent --max-time 5 --get --data-urlencode "payload=${payload}" --data-urlencode "signature=${signature}" "https://${vpn_gateway_ip}:19999/bindPort")

		if [ "$(echo "${bind_port}" | jq -r '.status')" != "OK" ]; then

			echo "[warn] Unable to bind port using URL 'https://${vpn_gateway_ip}:19999/bindPort'"
			retry_count=$((retry_count-1))
			echo "[info] ${retry_count} retries left"
			echo "[info] Retrying in ${retry_wait_secs} secs..."
			sleep "${retry_wait_secs}"s
			continue

		else

			# reset retry count on successful step
			retry_count=12

		fi

		echo "[info] Successfully assigned and bound incoming port '${port}'"

		# re-issue of bind required every 15 minutes
		sleep 15m

	done

}

function kill_openvpn() {

	echo "[warn] Attempting to allocate port failed, kill openvpn process to force retry of incoming port"
	kill -2 $(cat /root/openvpn.pid)
	# exit 1 required to stop infinite while loops, do not change to return 1
	exit 1

}

# check that app requires port forwarding and vpn provider is pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]] && [[ "${VPN_PROV}" == "pia" ]]; then

	if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

		echo "[info] Port forwarding is not enabled"

		# create empty incoming port file (read by downloader script)
		touch /tmp/getvpnport

	else

		# run legacy or next-gen scripts (depending on remote server hostname)
		if [[ "${vpn_remote_server}" == *"privacy.network"* ]]; then

			# pia api url for endpoint status (port forwarding enabled true|false)
			pia_vpninfo_api="https://serverlist.piaservers.net/vpninfo/servers/v4"

			# jq (json query tool) query to list port forward enabled servers by hostname (dns)
			jq_query_portforward_enabled='.regions | .[] | select(.port_forward=='true') | .dns'

			# jq (json query tool) query to select current vpn remote server (from ovpn file) and then get metadata server ip address
			jq_query_metadata_ip=".regions | .[] | select(.dns|tostring | contains(\"${vpn_remote_server}\")) | .servers | .meta | .[] | .ip"

			port_forward_status
			get_incoming_port_nextgen

		else

			# pia api url for endpoint status (port forwarding enabled true|false)
			pia_vpninfo_api="https://www.privateinternetaccess.com/vpninfo/servers?version=82"

			# jq (json query tool) query to select port forward and filter based only on port forward being enabled (true)
			jq_query_portforward_enabled='.[] | select(.port_forward|tostring | contains("true")) | .dns'

			port_forward_status
			get_incoming_port_legacy

		fi

	fi

else

	echo "[info] Application does not require port forwarding or VPN provider is != pia, skipping incoming port assignment"

fi
