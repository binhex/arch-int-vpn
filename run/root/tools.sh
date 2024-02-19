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
	docker_interfaces=$(ip link show | grep -v 'state DOWN' | cut -d ' ' -f 2 | grep -P -o '^[^@:]+' | grep -P -v "lo|${VPN_DEVICE_TYPE}" | xargs)

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
		docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's/^[[:space:]]*//')

		# append docker interface, gateway adapter, gateway ip, ip, mask and cidr to string
		docker_networking+="${docker_interface},${default_gateway_adapter},${default_gateway_ip},${docker_ip},${docker_mask},${docker_network_cidr} "

	done

	# remove trailing space
	docker_networking=$(echo "${docker_networking}" | sed -e 's/[[:space:]]*$//')

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Docker interface name, Gateway interface name, Gateway IP, Docker interface IP, Subnet mask and CIDR are defined as '${docker_networking}'" | ts '%Y-%m-%d %H:%M:%.S'
	fi

}

# this function must be run as root as it overwrites /etc/hosts
function resolve_vpn_endpoints() {

	# split comma separated string into list from VPN_REMOTE_SERVER variable
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

		# if the vpn_remote_server is NOT an ip address then resolve it
		if ! echo "${vpn_remote_server}" | grep -P -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then

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

						# dump associative array to file to be read back by /root/tools.sh
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

# function to check ip address is in valid format (used for local tunnel ip and external ip)
function check_valid_ip() {

	local_vpn_ip="$1"

	# check if the format looks right
	echo "${local_vpn_ip}" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || return 1

	# check that each octet is less than or equal to 255
	echo "${local_vpn_ip}" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <=255 && $4 <= 255 {print "Y" } ' | grep -q Y || return 1

	# check ip is not loopback or link local
	echo "${local_vpn_ip}" | grep '127.0.0.1' && return 1
	echo "${local_vpn_ip}" | grep -qE '169\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' && return 1

	return 0
}

# wait for valid ip for vpn adapter
function check_vpn_adapter_ip() {

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
	echo "${vpn_ip}" > /tmp/vpnip

}

# get vpn adapter gateway ip address
function get_vpn_gateway_ip() {

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Waiting for valid VPN gateway IP addresses from tunnel..."
	fi

	# wait for valid ip address for vpn adapter
	check_vpn_adapter_ip

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

	echo "${vpn_gateway_ip}" > '/tmp/vpngatewayip'

}