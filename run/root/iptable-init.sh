#!/bin/bash

function identify_docker_interface() {

	# identify docker bridge interface name by looking at defult route
	docker_interface=$(ip -4 route ls | grep default | xargs | grep -o -P '(?<=dev )([^\s]+)')
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Docker interface defined as ${docker_interface}" | ts '%Y-%m-%d %H:%M:%.S'
	fi
}

function add_vpn_endpoints_to_iptables_accept() {

	local direction="${1}"

	if [[ "${direction}" == "input" ]]; then
		io_flag="INPUT -i"
		srcdst_flag="-s"
	else
		io_flag="OUTPUT -o"
		srcdst_flag="-d"
	fi

	# iterate over remote ip address array and create accept rules
	for vpn_remote_ip_item in "${vpn_remote_ip_array[@]}"; do

		# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
		rule_exists=$(iptables -S | grep -e "-A ${io_flag} ${docker_interface} ${srcdst_flag} ${vpn_remote_ip_item} -j ACCEPT" || true)

		if [[ -z "${rule_exists}" ]]; then

			# accept input/output to remote vpn endpoint
			iptables -A ${io_flag} "${docker_interface}" ${srcdst_flag} "${vpn_remote_ip_item}" -j ACCEPT

		fi

	done

}

function resolve_vpn_endpoints() {

	# split comma separated string into list from VPN_REMOTE_SERVER variable
	IFS=',' read -ra vpn_remote_server_list <<< "${VPN_REMOTE_SERVER}"

	# initialise array used to store remote ip addresses for all remote endpoints
	vpn_remote_ip_array=()

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

			retry_count=12

			while true; do

				retry_count=$((retry_count-1))

				if [ "${retry_count}" -eq "0" ]; then

					echo "[crit] '${vpn_remote_server}' cannot be resolved, possible DNS issues, exiting..." | ts '%Y-%m-%d %H:%M:%.S' ; exit 1

				fi

				# resolve hostname to ip address(es)
				# note grep -m 8 is used to limit number of returned ip's per host to
				# 8 to reduce the change of hitting 64 remote options for openvpn
				vpn_remote_item_dns_answer=$(drill -a -4 "${vpn_remote_server}" | grep -v 'SERVER' | grep -m 8 -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | xargs)

				# check answer is not blank, if it is blank assume bad ns
				if [[ ! -z "${vpn_remote_item_dns_answer}" ]]; then

					if [[ "${DEBUG}" == "true" ]]; then
						echo "[debug] DNS operational, we can resolve name '${vpn_remote_server}' to address '${vpn_remote_item_dns_answer}'" | ts '%Y-%m-%d %H:%M:%.S'
					fi

					# append remote server ip addresses to the string using comma separators
					vpn_remote_ip_array+=(${vpn_remote_item_dns_answer})

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

			# if not blank then write to hosts file
			if [[ ! -z "${remote_dns_answer_first}" ]]; then
				echo "${remote_dns_answer_first}	${vpn_remote_server}" >> /etc/hosts
			fi

		else

			# append remote server ip addresses to the string using comma separators
			vpn_remote_ip_array+=(${vpn_remote_server})

		fi

	done

	# export all resolved vpn remote ip's - used in sourced openvpn.sh
	export vpn_remote_ip_array="${vpn_remote_ip_array}"
}

# call function to resolve all vpn endpoints
resolve_vpn_endpoints

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

# call function to identify docker interface
identify_docker_interface

# call function to add vpn remote endpoints to iptables input accept rule
add_vpn_endpoints_to_iptables_accept "input"

# call function to add vpn remote endpoints to iptables output accept rule
add_vpn_endpoints_to_iptables_accept "output"
