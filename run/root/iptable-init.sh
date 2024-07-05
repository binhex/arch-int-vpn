#!/bin/bash

function accept_vpn_endpoints() {

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

function drop_all_ipv4() {

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
}

function drop_all_ipv6() {

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
}

function name_resolution() {

	rule_flag="${1}"

	# permit queries to docker internal name server via any port
	#
	# note no port specified as docker randomises the port, run command 'iptables -L -v -t nat' to view docker internal
	# chain showing randomised port
	#
	# decent article discussing docker dns https://alex-v.blog/2019/12/13/quirks-of-dns-traffic-with-docker-compose/
	#
	iptables "${rule_flag}" INPUT -s 127.0.0.11/32 -j ACCEPT
	iptables "${rule_flag}" INPUT -d 127.0.0.11/32 -j ACCEPT

	iptables "${rule_flag}" OUTPUT -s 127.0.0.11/32 -j ACCEPT
	iptables "${rule_flag}" OUTPUT -d 127.0.0.11/32 -j ACCEPT

	# permit name resolution on port 53 for any ip
	#
	# note no ip specified due to the fact that a user can specify the name servers via docker and the query will then be
	# sent to 127.0.0.11 and forwarded onto the defined name servers
	#
	iptables "${rule_flag}" INPUT -p tcp -m tcp --sport 53 -j ACCEPT
	iptables "${rule_flag}" INPUT -p udp -m udp --sport 53 -j ACCEPT

	iptables "${rule_flag}" OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT
	iptables "${rule_flag}" OUTPUT -p udp -m udp --dport 53 -j ACCEPT

}

function add_name_servers() {

	# split comma separated string into list from NAME_SERVERS env variable
	IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Showing name servers in '/etc/resolv.conf' before overwrite from NAME_SERVERS..." | ts '%Y-%m-%d %H:%M:%.S'
		cat '/etc/resolv.conf' | ts '%Y-%m-%d %H:%M:%.S [debug]'
	fi

	# remove all existing name servers inherited from host
	> /etc/resolv.conf

	# process name servers in the list
	for name_server_item in "${name_server_list[@]}"; do

		# strip whitespace from start and end of name_server_item
		name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		# append name server to /etc/resolv.conf
		echo "nameserver ${name_server_item}" >> /etc/resolv.conf

	done

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Showing name servers in '/etc/resolv.conf' after overwrite from NAME_SERVERS..." | ts '%Y-%m-%d %H:%M:%.S'
		cat '/etc/resolv.conf' | ts '%Y-%m-%d %H:%M:%.S [debug]'
	fi

}

function main() {

	# drop all for ipv4
	drop_all_ipv4

	# drop all for ipv6
	drop_all_ipv6

	# source in tools script
	source tools.sh

	# insert accept name resolution rules
	name_resolution '-I'

	# call function from tools.sh to resolve all vpn endpoints
	resolve_vpn_endpoints

	# delete accept name resolution rules
	name_resolution '-D'

	# overwrite name servers using value from env var 'NAME_SERVERS'
	# Note we do this AFTER resolving vpn endpoints to permit name resolution
	# of the vpn endpoints using whatever the host has defined, including
	# local name servers - useful for pihole
	add_name_servers

	# run function from tools.sh to create global var 'docker_networking' used below
	get_docker_networking

	# call function to add vpn remote endpoints to iptables input accept rule
	accept_vpn_endpoints "input"

	# call function to add vpn remote endpoints to iptables output accept rule
	accept_vpn_endpoints "output"

}

main