#!/bin/bash

# initialise arrays for incoming ports
incoming_ports_ext_array=()
incoming_ports_lan_array=()

# append incoming ports for applications to arrays
if [[ "${APPLICATION}" == "qbittorrent" ]]; then
	incoming_ports_ext_array+=(${WEBUI_PORT})
elif [[ "${APPLICATION}" == "sabnzbd" ]]; then
	incoming_ports_ext_array+=(8080 8090)
elif [[ "${APPLICATION}" == "deluge" ]]; then
	incoming_ports_ext_array+=(8112)
	incoming_ports_lan_array+=(58846)
fi

# if microsocks enabled then add port for microsocks to incoming ports lan array
if [[ "${ENABLE_SOCKS}" == "yes" ]]; then
	incoming_ports_lan_array+=(9118)
fi

# if privoxy enabled then add port for privoxy to  incoming ports lan array
if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then
	incoming_ports_lan_array+=(8118)
fi

# source in tools script
source tools.sh

# run function from tools.sh, this creates global var 'docker_networking' used below
get_docker_networking

# if vpn input ports specified then add to incoming ports external array
if [[ -n "${VPN_INPUT_PORTS}" ]]; then

	# split comma separated string into array from VPN_INPUT_PORTS env variable
	IFS=',' read -ra vpn_input_ports_array <<< "${VPN_INPUT_PORTS}"

	# merge both arrays
	incoming_ports_ext_array=("${incoming_ports_ext_array[@]}" "${vpn_input_ports_array[@]}")

fi

# convert list of ip's back into an array (cannot export arrays in bash)
IFS=' ' read -ra vpn_remote_ip_array <<< "${VPN_REMOTE_IP_LIST}"

# if vpn output ports specified then add to outbound ports lan array
if [[ -n "${VPN_OUTPUT_PORTS}" ]]; then
	# split comma separated string into array from VPN_OUTPUT_PORTS env variable
	IFS=',' read -ra outgoing_ports_lan_array <<< "${VPN_OUTPUT_PORTS}"
fi

# array for both protocols
multi_protocol_array=(tcp udp)

# split comma separated string into array from LAN_NETWORK env variable
IFS=',' read -ra lan_network_array <<< "${LAN_NETWORK}"

# split comma separated string into array from VPN_REMOTE_PORT env var
IFS=',' read -ra vpn_remote_port_array <<< "${VPN_REMOTE_PORT}"

# ip route
###

# process lan networks in the array
for lan_network_item in "${lan_network_array[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# read in docker_networking from tools.sh, get 2nd and third values in first list item
	default_gateway_adapter="$(echo "${docker_networking}" | cut -d ',' -f 2 )"
	default_gateway_ip="$(echo "${docker_networking}" | cut -d ',' -f 3 )"

	echo "[info] Adding ${lan_network_item} as route via adapter ${default_gateway_adapter}"
	ip route add "${lan_network_item}" via "${default_gateway_ip}" dev "${default_gateway_adapter}"

done

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route s t all
echo "--------------------"

# iptables marks
###

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Modules currently loaded for kernel" ; lsmod
fi

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle
iptable_mangle_exit_code="${?}"

if [[ "${iptable_mangle_exit_code}" == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

	mark=0
	# required as path did not exist in latest tarball (20/09/2023)
	mkdir -p '/etc/iproute2'

	# setup route for application using set-mark to route traffic to lan
	for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

		mark=$((mark+1))
		echo "${incoming_ports_ext_item}    ${incoming_ports_ext_item}_${APPLICATION}" >> '/etc/iproute2/rt_tables'
		ip rule add fwmark "${mark}" table "${incoming_ports_ext_item}_${APPLICATION}"
		ip route add default via "${default_gateway_ip}" table "${incoming_ports_ext_item}_${APPLICATION}"

	done

fi

# input iptable rules
###

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
	docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

	# accept input to/from docker containers (172.x range is internal dhcp)
	iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

	for vpn_remote_ip_item in "${vpn_remote_ip_array[@]}"; do

		# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
		rule_exists=$(iptables -S | grep -e "-A INPUT -i ${docker_interface} -s ${vpn_remote_ip_item} -j ACCEPT")

		if [[ -z "${rule_exists}" ]]; then

			# return rule
			iptables -A INPUT -i "${docker_interface}" -s "${vpn_remote_ip_item}" -j ACCEPT

		fi

	done

done

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

	for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

		for vpn_remote_protocol_item in "${multi_protocol_array[@]}"; do

			# allows communication from any ip (ext or lan) to containers running in vpn network on specific ports
			iptables -A INPUT -i "${docker_interface}" -p "${vpn_remote_protocol_item}" --dport "${incoming_ports_ext_item}" -j ACCEPT

		done

	done

done

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
	docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

	# process lan networks in the array
	for lan_network_item in "${lan_network_array[@]}"; do

		# strip whitespace from start and end of lan_network_item
		lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		for incoming_ports_lan_item in "${incoming_ports_lan_array[@]}"; do

			# allows communication from lan ip to containers running in vpn network on specific ports
			iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -d "${docker_network_cidr}" -p tcp --dport "${incoming_ports_lan_item}" -j ACCEPT

		done

		for outgoing_ports_lan_item in "${outgoing_ports_lan_array[@]}"; do

			# return rule
			iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -d "${docker_network_cidr}" -p tcp --sport "${outgoing_ports_lan_item}" -j ACCEPT

		done

	done

done

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT

# output iptable rules
###

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

	# accept output to/from docker containers (172.x range is internal dhcp)
	iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

done

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

	# iterate over remote ip address array (from start.sh) and create accept rules
	for vpn_remote_ip_item in "${vpn_remote_ip_array[@]}"; do

		# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
		rule_exists=$(iptables -S | grep -e "-A OUTPUT -o ${docker_interface} -d ${vpn_remote_ip_item} -j ACCEPT")

		if [[ -z "${rule_exists}" ]]; then

			# accept output to remote vpn endpoint
			iptables -A OUTPUT -o "${docker_interface}" -d "${vpn_remote_ip_item}" -j ACCEPT

		fi

	done

done

# if iptable mangle is available (kernel module) then use mark
if [[ "${iptable_mangle_exit_code}" == 0 ]]; then

	mark=0

	for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

		mark=$((mark+1))
		# accept output from application - used for external access
		iptables -t mangle -A OUTPUT -p tcp --sport "${incoming_ports_ext_item}" -j MARK --set-mark "${mark}"

	done

fi

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

	for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

		for vpn_remote_protocol_item in "${multi_protocol_array[@]}"; do

			# return rule
			iptables -A OUTPUT -o "${docker_interface}" -p "${vpn_remote_protocol_item}" --sport "${incoming_ports_ext_item}" -j ACCEPT

		done

	done

done

# loop over docker adapters
for docker_network in ${docker_networking}; do

	# read in docker_networking from tools.sh
	docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
	docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

	# process lan networks in the array
	for lan_network_item in "${lan_network_array[@]}"; do

		# strip whitespace from start and end of lan_network_item
		lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		for incoming_ports_lan_item in "${incoming_ports_lan_array[@]}"; do

			# return rule
			iptables -A OUTPUT -o "${docker_interface}" -s "${docker_network_cidr}" -d "${lan_network_item}" -p tcp --sport "${incoming_ports_lan_item}" -j ACCEPT

		done

		for outgoing_ports_lan_item in "${outgoing_ports_lan_array[@]}"; do

			# allows communication from vpn network to containers running in lan network on specific ports
			iptables -A OUTPUT -o "${docker_interface}" -s "${docker_network_cidr}" -d "${lan_network_item}" -p tcp --dport "${outgoing_ports_lan_item}" -j ACCEPT

		done

	done

done

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

# accept output from tunnel adapter
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables -S 2>&1 | tee /tmp/getiptables
chmod +r /tmp/getiptables
echo "--------------------"
