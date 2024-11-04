#!/bin/bash

# this function must be run as root as it overwrites /etc/hosts
function round_robin_endpoint_ip() {

	# get endpoint names
	endpoint_name="${1}"

	# convert space separated ip's to array
	IFS=" " read -r -a endpoint_ip_array <<< "$2"

	# calculate number of ip's in the array
	# note need to -1 number as array index starts at 0
	ip_address_count_array=$((${#endpoint_ip_array[@]}-1))

	# get current ip address from /etc/hosts for this named endpoint
	current_ip=$(grep -P -o -m 1 ".*${endpoint_name}" < '/etc/hosts' | cut -f1)

	# get index number in array of current ip (if it exists, else -1)
	current_ip_index_number=-1
	for i in "${!endpoint_ip_array[@]}"; do
		if [[ "${endpoint_ip_array[$i]}" == "${current_ip}" ]]; then
			current_ip_index_number="${i}"
			break
		fi
	done

	# if current_ip_index_number is equal to number of ip's in the array or current ip
	# index number not found then get first ip in array (0), else get next ip in array
	if (( "${current_ip_index_number}" == "${ip_address_count_array}" || "${current_ip_index_number}" == -1 )); then
		next_ip=${endpoint_ip_array[0]}
	else
		index_number=$((current_ip_index_number+1))
		next_ip=${endpoint_ip_array[${index_number}]}
	fi

	# write ip address to /etc/hosts
	# note due to /etc/hosts being mounted we need to copy, edit, then overwrite
	cp -f '/etc/hosts' '/etc/hosts2'
	sed -i -e "s~.*${endpoint_name}~${next_ip}	${endpoint_name}~g" '/etc/hosts2'
	cp -f '/etc/hosts2' '/etc/hosts'
	rm -f '/etc/hosts2'

}

# this function works out what docker network interfaces we have available and returns a
# dictionary including gateway ip, gateway adapter, ip of adapter, subnet mask and cidr
# format of net mask
function get_docker_networking() {

	# get space seperated list of docker adapters, excluding loopback and vpn adapter
	docker_interfaces=$(ip link show | grep -v 'state DOWN' | cut -d ' ' -f 2 | grep -P -o '^[^@:]+' | grep -P -v "^(lo|${VPN_DEVICE_TYPE})$" | xargs)

	if [[ -z "${docker_interfaces}" ]]; then
		echo "[warn] Unable to identify Docker network interfaces, exiting script..."
		exit 1
	fi

	docker_networking=""

	for docker_interface in ${docker_interfaces}; do

		# identify adapter for local gateway
		default_gateway_adapter=$(ip route show default | awk '/default/ {print $5}')

		# identify ip for local gateway
		default_gateway_ip=$(ip route show default | awk '/default/ {print $3}')

		# identify ip for docker interface
		docker_ip=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=inet\s)[^\s]+')

		# identify netmask for docker interface
		docker_mask=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=netmask\s)[^\s]+')

		# convert netmask into cidr format, strip leading spaces
		if [[ "${docker_mask}" == "255.255.255.255" ]]; then
			# edge case where ipcalc does not work for networks with a single host, so we specify the cidr mask manually
			docker_network_cidr="${docker_ip}/32"
		else
			docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's/^[[:space:]]*//')
		fi

		# append docker interface, gateway adapter, gateway ip, ip, mask and cidr to string
		docker_networking+="${docker_interface},${default_gateway_adapter},${default_gateway_ip},${docker_ip},${docker_mask},${docker_network_cidr} "

	done

	# remove trailing space
	docker_networking=$(echo "${docker_networking}" | sed -e 's/[[:space:]]*$//')

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Docker interface name, Gateway interface name, Gateway IP, Docker interface IP, Subnet mask and CIDR are defined as '${docker_networking}'" | ts '%Y-%m-%d %H:%M:%.S'
	fi

}

# this function resolves name to ip address and writes out to /etc/hosts, we do this as we block
# all name lookups on the lan to prevent ip leakage and thus must be able to resolve all vpn
# endpoints that we may connect to.
# this function must be run as root as it overwrites /etc/hosts
function resolve_vpn_endpoints() {

	# split comma separated string into list from VPN_REMOTE_SERVER variable
	# shellcheck disable=SC2153
	IFS=',' read -ra vpn_remote_server_list <<< "${VPN_REMOTE_SERVER}"

	# initialise indexed array used to store remote ip addresses for all remote endpoints
	# note arrays are local to function unless -g flag is added
	declare -a vpn_remote_ip_array

	# initalise associative array used to store names and ip for remote endpoints
	# note arrays are local to function unless -g flag is added
	declare -A vpn_remote_array

	if [[ "${VPN_PROV}" == "pia" ]]; then

		# used to identify wireguard port for pia
		vpn_remote_server_list+=(www.privateinternetaccess.com)

		# used to retrieve list of port forward enabled endpoints for pia
		vpn_remote_server_list+=(serverlist.piaservers.net)

	fi

	# process remote servers in the array
	for vpn_remote_item in "${vpn_remote_server_list[@]}"; do

		vpn_remote_server=$(echo "${vpn_remote_item}" | tr -d ',')

		# if the vpn_remote_server is NOT an ip address (-v option) then resolve it
		# note -q prevents output to stdout
		if echo "${vpn_remote_server}" | grep -v -q -P -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then

			while true; do

				# resolve hostname to ip address(es)
				# note grep -m 8 is used to limit number of returned ip's per host to
				# 8 to reduce the change of hitting 64 remote options for openvpn
				vpn_remote_item_dns_answer=$(drill -a -4 "${vpn_remote_server}" | grep -v 'SERVER' | grep -m 8 -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)

				# check answer is not blank, if it is blank assume bad ns
				if [[ -n "${vpn_remote_item_dns_answer}" ]]; then

					if [[ "${DEBUG}" == "true" ]]; then
						echo "[debug] DNS operational, we can resolve name '${vpn_remote_server}' to address '${vpn_remote_item_dns_answer}'" | ts '%Y-%m-%d %H:%M:%.S'
					fi

					# append remote server ip addresses to the string using comma separators
					vpn_remote_ip_array+=(${vpn_remote_item_dns_answer})

					# filter out pia website (used for wireguard token) and serverlist (used to generate list of endpoints
					# with port forwarding enabled) as we do not need to rotate the ip for these and in fact rotating pia
					# website breaks the ability to get the token
					if [[ "${vpn_remote_item}" != "www.privateinternetaccess.com" && "${vpn_remote_item}" != "serverlist.piaservers.net" ]]; then

						# append endpoint name and ip addresses to associative array
						vpn_remote_array+=( ["${vpn_remote_server}"]="${vpn_remote_ip_array[@]}" )

						# dump associative array to file to be read back by tools.sh
						declare -p vpn_remote_array > '/tmp/endpoints'
					fi

					break

				else

					if [[ "${DEBUG}" == "true" ]]; then
						echo "[debug] Having issues resolving name '${vpn_remote_server}', sleeping before retry..." | ts '%Y-%m-%d %H:%M:%.S'
					fi
					sleep 5s

				fi

			done

			# get first ip from ${vpn_remote_item_dns_answer} and write to the hosts file
			# this is required as openvpn will use the remote entry in the ovpn file
			# even if you specify the --remote options on the command line, and thus we
			# must also be able to resolve the host name (assuming it is a name and not ip).
			remote_dns_answer_first=$(echo "${vpn_remote_item_dns_answer}" | cut -d ' ' -f 1)

			# if name not already in /etc/hosts file then write
			if ! grep -P -o -m 1 "${vpn_remote_server}" < '/etc/hosts'; then

				# if name resolution to ip is not blank then write to hosts file
				if [[ -n "${remote_dns_answer_first}" ]]; then
					echo "${remote_dns_answer_first}	${vpn_remote_server}" >> /etc/hosts
				fi

			fi

		else

			# append remote server ip addresses to the string using comma separators
			vpn_remote_ip_array+=(${vpn_remote_server})

		fi

	done

	# assign array to string (cannot export array in bash) and export for use with other scripts
	export VPN_REMOTE_IP_LIST="${vpn_remote_ip_array[*]}"
}

# wait for valid ip for vpn adapter - blocking
function get_vpn_adapter_ip() {

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Waiting for valid VPN adapter IP addresses from tunnel..."
	fi

	# loop and wait until tunnel adapter local ip is valid
	vpn_ip=""
	while ! check_valid_ip "${vpn_ip}"; do

		vpn_ip=$(ifconfig "${VPN_DEVICE_TYPE}" 2>/dev/null | grep 'inet' | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
		sleep 1s

	done

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Valid local IP address from tunnel acquired '${vpn_ip}'"
	fi

	# write ip address of vpn adapter to file, used in subsequent scripts
	echo "${vpn_ip}" > /tmp/getvpnip

}

# get vpn adapter gateway ip address - blocking
function get_vpn_gateway_ip() {

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Waiting for valid VPN gateway IP addresses from tunnel..."
	fi

	# wait for valid ip address for vpn adapter
	get_vpn_adapter_ip

	if [[ "${VPN_PROV}" == "protonvpn" ]]; then

		# get gateway ip, used for openvpn and wireguard to get port forwarding working via getvpnport.sh
		vpn_gateway_ip=""
		while ! check_valid_ip "${vpn_gateway_ip}"; do

			# use parameter expansion to convert last octet to 1 (gateway ip) from assigned vpn adapter ip
			vpn_gateway_ip=${vpn_ip%.*}.1

			sleep 1s

		done

	fi

	if [[ "${VPN_PROV}" == "pia" ]]; then

		# if empty get gateway ip (openvpn clients), otherwise skip (defined in wireguard.sh)
		if [[ -z "${vpn_gateway_ip}" ]]; then

			# get gateway ip, used for openvpn and wireguard to get port forwarding working via getvpnport.sh
			vpn_gateway_ip=""
			while ! check_valid_ip "${vpn_gateway_ip}"; do

				vpn_gateway_ip=$(ip route s t all | grep -m 1 "0.0.0.0/1 via .* dev ${VPN_DEVICE_TYPE}" | cut -d ' ' -f3)
				sleep 1s

			done

		fi

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Valid gateway IP address from tunnel acquired '${vpn_gateway_ip}'"
	fi

	echo "${vpn_gateway_ip}" > '/tmp/getvpngatewayip'

}

# this function checks dns is operational, a file is created if
# dns is not operational and this is monitored and picked up
# by the script /root/openvpn.sh and triggers a restart of the
# openvpn process.
function check_dns() {

	local hostname="${1}"

	if [[ "${VPN_ENABLED}" == "yes" ]]; then

		if [[ -z "${hostname}" ]]; then

			echo "[warn] No name argument passed, exiting script '${0}'..."
			exit 1

		fi

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] Checking we can resolve name '${hostname}' to address..."
		fi

		retry_count=12
		retry_wait=5

		while true; do

			# if file exists to denote tunnel is down (from openvpndown.sh or wireguarddown.sh) then break out of function
			if [[ -f '/tmp/tunneldown' ]]; then
				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Tunnel marked as down via file '/tmp/tunneldown', exiting function '${FUNCNAME[0]}'..."
				fi
				break
			fi

			retry_count=$((retry_count-1))

			if [ "${retry_count}" -eq "0" ]; then
				echo "[info] DNS failure, creating file '/tmp/dnsfailure' to indicate failure..."
				touch "/tmp/dnsfailure"
				chmod +r "/tmp/dnsfailure"
				break
			fi

			# check we can resolve names before continuing (required for tools.sh/get_vpn_external_ip)
			# note -v 'SERVER' is to prevent name server ip being matched from stdout
			remote_dns_answer=$(drill -a -4 "${hostname}" 2> /dev/null | grep -v 'SERVER' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)

			# check answer is not blank, if it is blank assume bad ns
			if [[ -n "${remote_dns_answer}" ]]; then

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] DNS operational, we can resolve name '${hostname}' to address '${remote_dns_answer}'"
				fi
				break

			else

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Having issues resolving name '${hostname}'"
					echo "[debug] Retrying in ${retry_wait} secs..."
					echo "[debug] ${retry_count} retries left"
				fi
				sleep "${retry_wait}s"

			fi

		done

	fi

}

# function to check incoming port is open (webscrape)
function check_incoming_port_webscrape() {

	incoming_port_check_url="${1}"
	post_data="${2}"
	regex_open="${3}"
	regex_closed="${4}"

	site_up="false"
	port_open="false"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
	fi

	# use curl to check incoming port is open (web scrape)
	if curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_open}" 1> /dev/null; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		site_up="true"
		port_open="true"
		return

	else

		# if port is not open then check we have a match for closed, if no match then suspect web scrape issue
		if curl --connect-timeout 30 --max-time 120 --silent --data "${post_data}" -X POST "${incoming_port_check_url}" | grep -i -P "${regex_closed}" 1> /dev/null; then

			echo "[info] ${APPLICATION} incoming port closed, marking for reconfigure"
			site_up="true"
			return

		else

			echo "[warn] Incoming port site '${incoming_port_check_url}' failed to web scrape, marking as failed"
			return

		fi

	fi

}

# function to check incoming port is open (json)
function check_incoming_port_json() {

	incoming_port_check_url="${1}"
	json_query="${2}"

	site_up="false"
	port_open="false"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Checking ${APPLICATION} incoming port '${!application_incoming_port}' is open, using external url '${incoming_port_check_url}'..."
	fi

	response=$(curl --connect-timeout 30 --max-time 120 --silent "${incoming_port_check_url}" | jq "${json_query}")

	if [[ "${response}" == "true" ]]; then

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ${APPLICATION} incoming port '${!application_incoming_port}' is open"
		fi
		site_up="true"
		port_open="true"
		return

	elif [[ "${response}" == "false" ]]; then

		echo "[info] ${APPLICATION} incoming port '${!application_incoming_port}' is closed, marking for reconfigure"
		site_up="true"
		return

	else

		echo "[warn] Incoming port site '${incoming_port_check_url}' failed json download, marking as failed"
		return

	fi

}

# function to call check_incoming_port_webscrape or check_incoming_port_json
function check_incoming_port() {

	# variable used below with bash indirect expansion
	application_incoming_port="${APPLICATION}_port"

	if [[ -z "${!application_incoming_port}" ]]; then
		echo "[warn] ${APPLICATION} incoming port is not defined" ; return 1
	fi

	if [[ -z "${external_ip}" ]]; then
		echo "[warn] External IP address is not defined" ; return 2
	fi

	# run function for first site (web scrape)
	check_incoming_port_webscrape "https://canyouseeme.org/" "port=${!application_incoming_port}&submit=Check" "success.*?on port.*?${!application_incoming_port}" "error.*?on port.*?${!application_incoming_port}"

	# if web scrape error/site down then try second site (json)
	if [[ "${site_up}" == "false" ]]; then
		check_incoming_port_json "https://ifconfig.co/port/${!application_incoming_port}" ".reachable"
	fi

	# if port down then mark as closed
	if [[ "${port_open}" == "false" ]]; then
		touch "/tmp/portclosed"
		return
	fi
}

# this function reads in the contents of a temporary file which contains the current
# iptables chain policies to check that they are in place before proceeding onto
# check tunnel connectivity. this file is generated by a line in the iptables.sh
# for the application container, and is removed at startup via the init.sh
# script. we use the temporary file to read in iptables chain policies, as we
# cannot perform any iptables instructions for non root users.
function check_iptables_drop() {

	# check /tmp/getiptables file exists
	if [ ! -f /tmp/getiptables ]; then
		return 1
	fi

	# check all chain policies are set to drop
	grep -q '\-P INPUT DROP' < /tmp/getiptables || return 1
	grep -q '\-P FORWARD DROP' < /tmp/getiptables || return 1
	grep -q '\-P OUTPUT DROP' < /tmp/getiptables || return 1

	return 0
}

# function to call check_iptables_drop
function check_iptables() {
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Waiting for iptables chain policies to be in place..."
	fi

	# loop and wait until iptables chain policies are in place
	while ! check_iptables_drop
	do
		sleep 0.1
	done

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] iptables chain policies are in place"
	fi
}

# function to read the assigned vpn incoming port from the file
# "/tmp/getvpnextip", created by function get_vpn_external_ip
function check_vpn_external_ip() {

	while [ ! -f /tmp/getvpnextip ]
	do
		sleep 0.1s
	done

	# get vpn external ip address (file contents generated by tools.sh/get_vpn_external_ip)
	external_ip=$(</tmp/getvpnextip)

}

# function to read the assigned vpn incoming port from the file
# "/tmp/getvpnip", created by function get_vpn_adapter_ip
function check_vpn_tunnel_ip() {

	while [ ! -f /tmp/getvpnip ]
	do
		sleep 0.1s
	done

	# get vpn tunnel ip address (file contents generated by tools.sh)
	vpn_ip=$(</tmp/getvpnip)
}

# function to read the assigned vpn incoming port from the file
# "/tmp/getvpnport", created by function get_vpn_incoming_port
function check_vpn_incoming_port() {

	# check that app requires port forwarding and vpn provider is pia
	if [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]]; then

		vpn_port="/tmp/getvpnport"

		while [ ! -f "${vpn_port}" ]
		do
			sleep 1s
		done

		VPN_INCOMING_PORT=$(<"${vpn_port}")

	fi

}

# function to check ip address is in correct format
function check_valid_ip() {

	check_ip="$1"

	# check if the format looks right
	echo "${check_ip}" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octect is less than or equal to 255
	echo "${check_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	return 0
}

# function to get external ip using website lookup
function get_external_ip_web() {

	site="${1}"

	external_ip="$(curl --connect-timeout "${curl_connnect_timeout_secs}" --max-time "${curl_max_time_timeout_secs}" --interface "${vpn_ip}" "${site}" 2> /dev/null | grep -P -o -m 1 '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"

	check_valid_ip "${external_ip}"
	return_code="$?"

	# if empty value returned, or ip not in correct format then try primary url
	if [[ -z "${external_ip}" || "${return_code}" != 0 ]]; then

		echo "1"

	else

		# write external ip address to text file, this is then read by the downloader script
		echo "${external_ip}" > /tmp/getvpnextip

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /tmp/getvpnextip

		echo "${external_ip}"

	fi

}

function get_vpn_external_ip() {

	# define timeout periods
	curl_connnect_timeout_secs=10
	curl_max_time_timeout_secs=30

	if [[ -z "${vpn_ip}" ]]; then
		echo "[warn] VPN IP address is not defined or is an empty string"
		return 1
	fi

	site="http://checkip.amazonaws.com"

	echo "[info] Attempting to get external IP using '${site}'..."
	result=$(get_external_ip_web "${site}")

	if [ "${result}" == "1" ]; then

		site="http://whatismyip.akamai.com"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}")

	fi

	if [ "${result}" == "1" ]; then

		site="https://ifconfig.co/ip"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}")

	fi

	if [ "${result}" == "1" ]; then

		site="https://showextip.azurewebsites.net"

		echo "[info] Failed on last attempt, attempting to get external IP using '${site}'..."
		result=$(get_external_ip_web "${site}")

	fi

	if [ "${result}" == "1" ]; then

		echo "[warn] Cannot determine external IP address, performing tests before setting to '127.0.0.1'..."
		echo "[info] Show name servers defined for container" ; cat /etc/resolv.conf
		echo "[info] Show contents of hosts file" ; cat /etc/hosts

		# write external ip address to text file, this is then read by the downloader script
		echo "127.0.0.1" > /tmp/getvpnextip

		# chmod file to prevent restrictive umask causing read issues for user nobody (owner is user root)
		chmod +r /tmp/getvpnextip

		return 1

	else

		echo "[info] Successfully retrieved external IP address ${result}"
		return 0

	fi

}

#
# port forwarding

function pia_port_forward_check() {

	echo "[info] Port forwarding is enabled"
	echo "[info] Checking endpoint '${VPN_REMOTE_SERVER}' is port forward enabled..."

	# run curl to grab api result
	jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

	if [[ -z "${jq_query_result}" ]]; then
		echo "[warn] PIA endpoint API '${pia_vpninfo_api}' currently down, skipping endpoint port forward check"
		return 1
	fi

	# run jq query to get endpoint name (dns) only, use xargs to turn into single line string
	jq_query_details=$(echo "${jq_query_result}" | jq -r "${jq_query_portforward_enabled}" 2> /dev/null | xargs)

	if [[ -z "${jq_query_details}" ]]; then
		echo "[warn] Json query '${jq_query_portforward_enabled}' returns empty result for port forward enabled servers, skipping endpoint port forward check"
		return 1
	fi

	# run grep to check that defined vpn remote is in the list of port forward enabled endpoints
	# grep -w = exact match (whole word), grep -q = quiet mode (no output)
	if echo "${jq_query_details}" | grep -qw "${VPN_REMOTE_SERVER}"; then

		echo "[info] PIA endpoint '${VPN_REMOTE_SERVER}' is in the list of endpoints that support port forwarding shown below:-"
		pia_port_forward_list
		return 0

	else

		echo "[info] PIA endpoint '${VPN_REMOTE_SERVER}' is NOT in the list of endpoints that support port forwarding shown below:-"
		pia_port_forward_list
		return 1

	fi

}

function pia_port_forward_list() {

	# run curl to grab api result
	jq_query_result=$(curl --silent --insecure "${pia_vpninfo_api}")

	# run jq query to get endpoint name (dns) only, use xargs to turn into single line string
	jq_query_details=$(echo "${jq_query_result}" | jq -r "${jq_query_portforward_enabled}" 2> /dev/null | xargs)

	# convert to list with separator being space
	IFS=' ' read -ra jq_query_details_list <<< "${jq_query_details}"

	echo "[info] List of PIA endpoints that support port forwarding:-"

	# loop over list of port forward enabled endpooints and echo out to console
	for i in "${jq_query_details_list[@]}"; do
			echo "[info] ${i}"
	done

}

function pia_assign_incoming_port() {

	retry_count=12
	retry_wait_secs=10

	# run function from tools.sh
	get_vpn_gateway_ip

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Unable to download PIA json to generate token for port forwarding, creating file '/tmp/portfailure' to indicate failure..."
			touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1

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

			echo "[warn] Unable to download PIA json payload, creating file '/tmp/portfailure' to indicate failure..."
			touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1

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

	if [[ -n "${payload_decoded}" ]]; then

		port=$(echo "${payload_decoded}" | jq -r '.port')
		# note expires_at time in this format'2020-11-24T22:12:07.627551124Z'
		expires_at=$(echo "${payload_decoded}" | jq -r '.expires_at')

		if [[ "${DEBUG}" == "true" ]]; then

			echo "[debug] PIA generated 'token' for port forwarding is '${token}'"
			echo "[debug] PIA assigned incoming port is'${port}'"
			echo "[debug] PIA port forward assigned expires on '${expires_at}'"

		fi

	else

		echo "[warn] Unable to decode payload, creating file '/tmp/portfailure' to indicate failure..."
		touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1

	fi

	if [[ "${port}" =~ ^-?[0-9]+$ ]]; then

		# write port number to text file (read by downloader script)
		echo "${port}" > /tmp/getvpnport

		# if /shared directory exists then copy from /tmp/getvpnport
		if [[ -d '/shared' ]]; then
			cp -f /tmp/getvpnport /shared/getvpnport
		fi

	else

		echo "[warn] Incoming port assigned is not a decimal value '${port}', creating file '/tmp/portfailure' to indicate failure..."
		touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1

	fi

	# run function to bind port every 15 minutes
	pia_keep_incoming_port_alive

}

function pia_keep_incoming_port_alive() {

	retry_count=12
	retry_wait_secs=10

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Running infinite while loop to keep assigned incoming port for PIA live..."
	fi

	while true; do

		if [ "${retry_count}" -eq "0" ]; then

			echo "[warn] Unable to bind incoming port '${port}', creating file '/tmp/portfailure' to indicate failure..."
			touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1

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
		sleep 10m & wait $!

	done

}

function protonvpn_port_forward_check() {

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

function protonvpn_assign_incoming_port() {

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Running infinite while loop to keep assigned incoming port for ProtonVPN live..."
	fi

	while true; do

		protocol_list="UDP TCP"

		for protocol in ${protocol_list}; do

			# assign incoming port for udp/tcp
			port=$(natpmpc -g "${vpn_gateway_ip}" -a 1 0 "${protocol}" 60 | grep -P -o -m 1 '(?<=Mapped public port\s)\d+')
			if [ -z "${port}" ]; then
				echo "[warn] Unable to assign an incoming port for protocol ${protocol}, creating file '/tmp/portfailure' to indicate failure..."
				touch "/tmp/portfailure" && chmod +r "/tmp/portfailure" ; return 1
			fi

		done

		if [[ "${DEBUG}" == "true" ]]; then
			echo "[debug] ProtonVPN assigned incoming port is '${port}'"
		fi

		# write port number to text file (read by downloader script)
		echo "${port}" > /tmp/getvpnport

		# if /shared directory exists then copy from /tmp/getvpnport
		if [[ -d '/shared' ]]; then
			cp -f /tmp/getvpnport /shared/getvpnport
		fi

		# we need to poll AT LEAST every 60 seconds to keep the port open
		sleep 45s & wait $!

	done
}

function get_vpn_incoming_port() {

	if [[ "${VPN_PROV}" == "protonvpn" ]]; then

		if [[ "${STRICT_PORT_FORWARD}" == "no" ]]; then

			echo "[info] Port forwarding is not enabled"

			# create empty incoming port file (read by downloader script)
			touch /tmp/getvpnport

		else

			echo "[info] Script started to assign incoming port for '${VPN_PROV}'"

			# write pid of this script to file, this file is then used to kill this script if openvpn/wireguard restarted/killed
			echo "${BASHPID}" > '/tmp/getvpnport.pid'

			# check whether endpoint is enabled for port forwarding and username has correct suffix
			if protonvpn_port_forward_check; then

				# assign incoming port - blocking as in infinite while loop
				protonvpn_assign_incoming_port

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

			# pia api url for endpoint status (port forwarding enabled true|false)
			pia_vpninfo_api="https://serverlist.piaservers.net/vpninfo/servers/v4"

			# jq (json query tool) query to list port forward enabled servers by hostname (dns)
			jq_query_portforward_enabled='.regions | .[] | select(.port_forward==true) | .dns'

			# check whether endpoint is enabled for port forwarding
			if pia_port_forward_check; then

				# assign incoming port - blocking as in infinite while loop
				pia_assign_incoming_port

			fi

			echo "[info] Script finished to assign incoming port"

		fi

	else

		echo "[info] VPN provider '${VPN_PROV}' not supported for automatic port forwarding, skipping incoming port assignment"

	fi

}
