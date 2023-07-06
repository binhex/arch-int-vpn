#!/bin/bash

# check endpoint is port forward enabled (pia only)
function pia_port_forward_status() {

	echo "[info] Port forwarding is enabled"

	echo "[info] Checking endpoint '${VPN_REMOTE_SERVER}' is port forward enabled..."

	# run curl to grab api result
	jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

	if [[ "${?}" != 0 ]]; then

		echo "[warn] PIA VPN info API currently down, skipping endpoint port forward check"

	else

		# run jq query to get endpoint name (dns) only, use xargs to turn into single line string
		jq_query_details=$(echo "${jq_query_result}" | jq -r "${jq_query_portforward_enabled}" 2> /dev/null | xargs)

		# run grep to check that defined vpn remote is in the list of port forward enabled endpoints
		# grep -w = exact match (whole word), grep -q = quiet mode (no output)
		echo "${jq_query_details}" | grep -qw "${VPN_REMOTE_SERVER}"

		if [[ "${?}" != 0 ]]; then

			echo "[warn] PIA endpoint '${VPN_REMOTE_SERVER}' is not in the list of endpoints that support port forwarding, DL/UL speeds maybe slow"
			echo "[info] Please consider switching to one of the endpoints shown below"

		else

			echo "[info] PIA endpoint '${VPN_REMOTE_SERVER}' is in the list of endpoints that support port forwarding"

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

function protonvpn_port_forward_status() {
	set -x
	# get vpn local ip (not used) and gateway ip
	source /root/tools.sh

	# run function from tools.sh
	get_vpn_gateway_ip

	# check if username has the required suffix of '+pmp'
	if [[ "${VPN_USER}" != *"+pmp"* ]]; then
		echo "[info] ProtonVPN username '${VPN_USER}' does not contain the suffix '+pmp' and therefore is not enabled for port forwarding, skipping port forward assignment..."
		return 1
	fi

	# check if endpoint is enabled for p2p
	if ! natpmpc -g "${vpn_gateway_ip}"; then
		echo "[warn] ProtonVPN endpoint '${VPN_REMOTE_SERVER}' is not enabled for P2P port forwarding, skipping port forward assignment..."
		return 1
	fi
	return 0

}


# attempt to get incoming port (pia only)
function pia_get_incoming_port() {

	retry_count=12
	retry_wait_secs=10

	while true; do

		# get vpn local ip (not used) and gateway ip
		source /root/tools.sh

		# run function from tools.sh
		get_vpn_gateway_ip

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Unable to download PIA json to generate token for port forwarding, exiting script..."
				trigger_failure ; return 1

			fi

			# get token json response AFTER vpn established
			# note binding to the vpn interface (using --interface flag for curl) is required
			# due to users potentially using the 10.x.x.x range for lan, causing failure
			token_json_response=$(curl --interface "${VPN_DEVICE_TYPE}" --silent --insecure -u "${VPN_USER}:${VPN_PASS}" "https://www.privateinternetaccess.com/gtoken/generateToken")

			if [ "$(echo "${token_json_response}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json to generate token from URL 'https://www.privateinternetaccess.com/gtoken/generateToken'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s & wait $!

			else

				# get token
				token=$(echo "${token_json_response}" | jq -r '.token')

				# reset retry count on successful step
				retry_count=12
				break

			fi

		done

		while true; do

			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Unable to download PIA json payload, exiting script..."
				trigger_failure ; return 1

			fi

			# get payload and signature
			# note use of urlencode, this is required, otherwise login failure can occur
			payload_and_sig=$(curl --interface "${VPN_DEVICE_TYPE}" --insecure --silent --max-time 5 --get --data-urlencode "token=${token}" "https://${vpn_gateway_ip}:19999/getSignature")

			if [ "$(echo "${payload_and_sig}" | jq -r '.status')" != "OK" ]; then

				echo "[warn] Unable to successfully download PIA json payload from URL 'https://${vpn_gateway_ip}:19999/getSignature' using token '${token}'"
				echo "[info] ${retry_count} retries left"
				echo "[info] Retrying in ${retry_wait_secs} secs..."
				retry_count=$((retry_count-1))
				sleep "${retry_wait_secs}"s & wait $!

			else

				# reset retry count on successful step
				retry_count=12
				break

			fi

		done

		payload=$(echo "${payload_and_sig}" | jq -r '.payload')
		signature=$(echo "${payload_and_sig}" | jq -r '.signature')

		# decode payload to get port, and expires date (2 months)
		payload_decoded=$(echo "${payload}" | base64 -d | jq)

		if [ "${?}" -eq 0 ]; then

			port=$(echo "${payload_decoded}" | jq -r '.port')
			# note expires_at time in this format'2020-11-24T22:12:07.627551124Z'
			expires_at=$(echo "${payload_decoded}" | jq -r '.expires_at')

			if [[ "${DEBUG}" == "true" ]]; then

				echo "[debug] PIA generated 'token' for port forwarding is '${token}'"
				echo "[debug] PIA port forward assigned is '${port}'"
				echo "[debug] PIA port forward assigned expires on '${expires_at}'"

			fi

		else

			echo "[warn] Unable to decode payload, exiting script..."
			trigger_failure ; return 1

		fi

		if [[ "${port}" =~ ^-?[0-9]+$ ]]; then

			# write port number to text file (read by downloader script)
			echo "${port}" > /tmp/getvpnport

		else

			echo "[warn] Incoming port assigned is not a decimal value '${port}', exiting script..."
			trigger_failure ; return 1

		fi

		# run function to bind port every 15 minutes (background)
		pia_keep_incoming_port_alive &

		# current time in GMT minus 2 hours to ensure we are within the 2 month time period, compared to epoch
		current_datetime_epoch=$(TZ=GMT date -d '2 hour ago' +%s)

		# expires_at datetime as a date object in current time format, compared to epoch
		expires_at_convert_epoch=$(date -d "${expires_at}" +%s)

		# calculate time left before port expires
		expires_at_delta=$(( expires_at_convert_epoch - current_datetime_epoch ))

		# sleep for time difference
		sleep "${expires_at_delta}"s & wait $!

	done

}

function protonvpn_get_incoming_port() {

	protocol_list="UDP TCP"

	for protocol in ${protocol_list}; do

		# create a port forward for udp/tcp port
		port=$(natpmpc -g "${vpn_gateway_ip}" -a 0 0 "${protocol}" 60 | grep -P -o -m 1 '(?<=Mapped public port\s)\d+')
		if [ -z "${port}" ]; then
			echo "[warn] Unable to assign an incoming port for protocol ${protocol}, returning 1 from function..."
			return 1
		fi

	done

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] ProtonVPN assigned incoming port is '${port}'"
	fi

	# write port number to text file (read by downloader script)
	echo "${port}" > /tmp/getvpnport

	return 0

}

function protonvpn_keep_incoming_port_alive() {

	# run function to set trap so we exit cleanly when kill issued
	# due to this function running in background we need to set trap here as well as main
	set_trap

	retry_count=12
	retry_wait_secs=10

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Unable to bind incoming port '${port}', exiting script..."
			trigger_failure ; return 1

		fi

		if ! protonvpn_get_incoming_port; then

			echo "[warn] Unable to assign incoming port"
			retry_count=$((retry_count-1))
			echo "[info] ${retry_count} retries left"
			echo "[info] Retrying in ${retry_wait_secs} secs..."
			sleep "${retry_wait_secs}"s & wait $!
			continue

		else

			# reset retry count on successful step
			retry_count=12

		fi

		echo "[info] Successfully assigned and bound incoming port '${port}'"

		# we need to poll AT LEAST every 60 seconds to keep the port open
		sleep 45s & wait $!

	done
}

function pia_keep_incoming_port_alive() {

	# run function to set trap so we exit cleanly when kill issued
	# due to this function running in background we need to set trap here as well as main
	set_trap

	retry_count=12
	retry_wait_secs=10

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Unable to bind incoming port '${port}', exiting script..."
			trigger_failure ; return 1

		fi

		# note use of urlencode, this is required, otherwise login failure can occur
		bind_port=$(curl --interface "${VPN_DEVICE_TYPE}" --insecure --silent --max-time 5 --get --data-urlencode "payload=${payload}" --data-urlencode "signature=${signature}" "https://${vpn_gateway_ip}:19999/bindPort")

		if [ "$(echo "${bind_port}" | jq -r '.status')" != "OK" ]; then

			echo "[warn] Unable to bind port using URL 'https://${vpn_gateway_ip}:19999/bindPort'"
			retry_count=$((retry_count-1))
			echo "[info] ${retry_count} retries left"
			echo "[info] Retrying in ${retry_wait_secs} secs..."
			sleep "${retry_wait_secs}"s & wait $!
			continue

		else

			# reset retry count on successful step
			retry_count=12

		fi

		echo "[info] Successfully assigned and bound incoming port '${port}'"

		# we need to poll AT LEAST every 15 minutes to keep the port open
		sleep 15m & wait $!

	done

}

function trigger_failure() {

	echo "[info] Port forwarding failure, creating file '/tmp/portfailure' to indicate failure..."
	touch "/tmp/portfailure"
	chmod +r "/tmp/portfailure"

}

function set_trap() {

	# trap kill signal INT (-2), TERM (-15) or EXIT (internal bash).
	# kill all child processes and exit with exit code 1
	# required to allow us to stop this script as it has several sleep
	# commands and background function
	trap 'kill $(jobs -p); exit 1' INT TERM EXIT

}

# check that app requires port forwarding and vpn provider is pia (note this env var is passed through to up script via openvpn --sentenv option)
if [[ "${APPLICATION}" != "sabnzbd" ]] && [[ "${APPLICATION}" != "privoxy" ]]; then

	if [[ "${VPN_PROV}" == "protonvpn" ]]; then

		if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

			echo "[info] Port forwarding is not enabled"

			# create empty incoming port file (read by downloader script)
			touch /tmp/getvpnport

		else

			echo "[info] Script started to assign incoming port for '${VPN_PROV}'"

			# write pid of this script to file, this file is then used to kill this script if openvpn/wireguard restarted/killed
			echo "${BASHPID}" > '/tmp/getvpnport.pid'

			# run function to set trap so we exit cleanly when kill issued
			set_trap

			# check whether endpoint is enabled for port forwarding and username has correct suffix
			if protonvpn_port_forward_status; then

				# get incoming port - blocking as in infinite while loop
				protonvpn_keep_incoming_port_alive

			fi

			echo "[info] Script finished to assign incoming port"

		fi

	elif [[ "${VPN_PROV}" == "pia" ]]; then

		if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

			echo "[info] Port forwarding is not enabled"

			# create empty incoming port file (read by downloader script)
			touch /tmp/getvpnport

		else

			echo "[info] Script started to assign incoming port for '${VPN_PROV}'"

			# write pid of this script to file, this file is then used to kill this script if openvpn/wireguard restarted/killed
			echo "${BASHPID}" > '/tmp/getvpnport.pid'

			# run function to set trap so we exit cleanly when kill issued
			set_trap

			# pia api url for endpoint status (port forwarding enabled true|false)
			pia_vpninfo_api="https://serverlist.piaservers.net/vpninfo/servers/v4"

			# jq (json query tool) query to list port forward enabled servers by hostname (dns)
			jq_query_portforward_enabled='.regions | .[] | select(.port_forward=='true') | .dns'

			# jq (json query tool) query to select current vpn remote server (from env var) and then get metadata server ip address
			jq_query_metadata_ip=".regions | .[] | select(.dns | match(\"^${VPN_REMOTE_SERVER}\")) | .servers | .meta | .[] | .ip"

			# check whether endpoint is enabled for port forwarding
			pia_port_forward_status

			# get incoming port
			pia_get_incoming_port

			echo "[info] Script finished to assign incoming port"

		fi

	else

		echo "[info] VPN provider '${VPN_PROV}' not supported for automatic port forwarding, skipping incoming port assignment"

	fi

else

	echo "[info] Application does not require port forwarding, skipping incoming port assignment"

fi
