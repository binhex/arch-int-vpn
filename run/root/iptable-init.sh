#!/bin/bash

function add_vpn_endpoints_to_iptables_accept() {

	local direction="${1}"

	if [[ "${direction}" == "input" ]]; then
		io_flag="INPUT -i"
		srcdst_flag="-s"
	else
		io_flag="OUTPUT -o"
		srcdst_flag="-d"
	fi

	# convert list of ip's back into an array (cannot export arrays in bash)
	IFS=' ' read -ra vpn_remote_ip_array <<< "${VPN_REMOTE_IP_LIST}"

	for docker_network in ${docker_networking}; do

		# read in docker_networking from tools.sh
		docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

		# iterate over remote ip address array and create accept rules
		for vpn_remote_ip_item in "${vpn_remote_ip_array[@]}"; do

			# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
			rule_exists=$(iptables -S | grep -e "-A ${io_flag} ${docker_interface} ${srcdst_flag} ${vpn_remote_ip_item} -j ACCEPT" || true)

			if [[ -z "${rule_exists}" ]]; then

				# accept input/output to remote vpn endpoint
				iptables -A ${io_flag} "${docker_interface}" ${srcdst_flag} "${vpn_remote_ip_item}" -j ACCEPT

			fi

		done
		
	done
}

# sounrce in function to resolve endpoints
source '/root/tools.sh'

# call function to resolve all vpn endpoints
resolve_vpn_endpoints

# run function from tools.sh, this creates global var 'docker_networking' used below
get_docker_networking

# check and set iptables drop
if ! iptables -S | grep '^-P' > /dev/null 2>&1; then

        echo "[crit] iptables default policies not available, exiting script..." | ts '%Y-%m-%d %H:%M:%.S'
		exit 1

else

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] iptables default policies available, setting policy to drop..." | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# set policy to drop ipv4 for input
	iptables -P INPUT DROP > /dev/null

	# set policy to drop ipv4 for forward
	iptables -P FORWARD DROP > /dev/null

	# set policy to drop ipv4 for output
	iptables -P OUTPUT DROP > /dev/null

fi

# check and set ip6tables drop
if ! ip6tables -S | grep '^-P' > /dev/null 2>&1; then

        echo "[warn] ip6tables default policies not available, skipping ip6tables drops" | ts '%Y-%m-%d %H:%M:%.S'

else

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] ip6tables default policies available, setting policy to drop..." | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# set policy to drop ipv6 for input
	ip6tables -P INPUT DROP > /dev/null

	# set policy to drop ipv6 for forward
	ip6tables -P FORWARD DROP > /dev/null

	# set policy to drop ipv6 for output
	ip6tables -P OUTPUT DROP > /dev/null

fi

# call function to add vpn remote endpoints to iptables input accept rule
add_vpn_endpoints_to_iptables_accept "input"

# call function to add vpn remote endpoints to iptables output accept rule
add_vpn_endpoints_to_iptables_accept "output"
