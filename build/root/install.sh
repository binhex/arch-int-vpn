#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# detect image arch
####

OS_ARCH=$(cat /etc/os-release | grep -P -o -m 1 "(?=^ID\=).*" | grep -P -o -m 1 "[a-z]+$")
if [[ ! -z "${OS_ARCH}" ]]; then
	if [[ "${OS_ARCH}" == "arch" ]]; then
		OS_ARCH="x86-64"
	else
		OS_ARCH="aarch64"
	fi
	echo "[info] OS_ARCH defined as '${OS_ARCH}'"
else
	echo "[warn] Unable to identify OS_ARCH, defaulting to 'x86-64'"
	OS_ARCH="x86-64"
fi

# pacman packages
####

# define pacman packages
pacman_packages="kmod openvpn privoxy bind-tools gnu-netcat ipcalc wireguard-tools openresolv"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# env vars
####

cat <<'EOF' > /tmp/envvars_common_heredoc

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	if [ "${VPN_ENABLED}" != "no" ] && [ "${VPN_ENABLED}" != "No" ] && [ "${VPN_ENABLED}" != "NO" ]; then
		export VPN_ENABLED="yes"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_ENABLED="no"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[warn] !!IMPORTANT!! VPN IS SET TO DISABLED', YOU WILL NOT BE SECURE" | ts '%Y-%m-%d %H:%M:%.S'
	fi
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ "${VPN_ENABLED}" == "yes" ]]; then

	# get values from env vars as defined by user
	export VPN_CLIENT=$(echo "${VPN_CLIENT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_CLIENT}" ]]; then
		echo "[info] VPN_CLIENT defined as '${VPN_CLIENT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] VPN_CLIENT not defined (via -e VPN_CLIENT), defaulting to 'openvpn'" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_CLIENT="openvpn"
	fi

	# get values from env vars as defined by user
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	if [[ "${VPN_PROV}" == "pia" ]]; then

		pia_vpninfo_api_url="https://serverlist.piaservers.net/vpninfo/servers/v4"

		# export vpninfo json as this is used in getvpnport.sh and wireguard.sh
		export PIA_VPNINFO_API=$(curl --silent "${pia_vpninfo_api_url}")

		if [[ -z "${PIA_VPNINFO_API}" ]]; then

			if [[ "${VPN_CLIENT}" == "wireguard" ]]; then
				echo "[crit] PIA VPN server info JSON cannot be downloaded from URL '${pia_vpninfo_api_url}' exit code from curl is '${?}', exiting..." | ts '%Y-%m-%d %H:%M:%.S'
				exit 1
			else
				echo "[warn] PIA VPN server info JSON cannot be downloaded from URL '${pia_vpninfo_api_url}' exit code from curl is '${?}'" | ts '%Y-%m-%d %H:%M:%.S'
			fi

		fi

	fi

	if [[ "${VPN_CLIENT}" == "wireguard" ]]; then

		# create directory to store wireguard config files
		mkdir -p /config/wireguard

		# set perms and owner for files in /config/wireguard directory
		set +e
		chown -R "${PUID}":"${PGID}" "/config/wireguard" &> /dev/null
		exit_code_chown=$?
		chmod -R 775 "/config/wireguard" &> /dev/null
		exit_code_chmod=$?
		set -e

		if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
			echo "[warn] Unable to chown/chmod /config/wireguard/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		# force removal of mac os resource fork files in wireguard folder
		rm -rf /config/wireguard/._*.conf

		# wildcard search for wireguard config files (match on first result)
		vpn_config_path=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)

		if [[ -z "${vpn_config_path}" ]]; then

			if [[ "${VPN_PROV}" == "pia" ]]; then

				# if conf file not found in /config/wireguard then set defaults, wireguard config
				# file for pia will be dynamically generated and visible on next startup

				echo "[info] VPN_CONFIG not defined (wireguard config doesnt file exists), defaulting to '/config/wireguard/wg0.conf'" | ts '%Y-%m-%d %H:%M:%.S'
				export VPN_CONFIG="/config/wireguard/wg0.conf"

				echo "[info] VPN_REMOTE_SERVER not defined (wireguard config doesnt file exists), defaulting to 'nl-amsterdam.privacy.network'" | ts '%Y-%m-%d %H:%M:%.S'
				export VPN_REMOTE_SERVER="nl-amsterdam.privacy.network"

				# get wireguard port from pia api, as the port could change
				jq_query_wg_ports=".groups | .wg | .[] | .ports[]"
				export VPN_REMOTE_PORT=$(echo "${PIA_VPNINFO_API}" | jq -r "${jq_query_wg_ports}" 2> /dev/null)

				if [[ -z "${VPN_REMOTE_PORT}" ]]; then
					echo "[info] VPN_REMOTE_PORT not defined (wireguard config file doesnt exists), defaulting to '1337'" | ts '%Y-%m-%d %H:%M:%.S'
					export VPN_REMOTE_PORT="1337"
				else
					echo "[info] VPN_REMOTE_PORT not defined (wireguard config file doesnt exists), identified port as '${VPN_REMOTE_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
				fi

			else

				# if conf file not found in /config/wireguard and provider is not pia then exit
				echo "[crit] No WireGuard config file located in /config/wireguard/ (conf extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1

			fi

		else

			# rename wireguard config file to prevent issues with spaces and other illegal characters for device
			export  VPN_CONFIG="/config/wireguard/wg0.conf"
			if [[ $(basename "${vpn_config_path}") != wg0.conf ]]; then
				mv "${vpn_config_path}" "${VPN_CONFIG}"
			fi
			echo "[info] WireGuard config file (conf extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

			# convert CRLF (windows) to LF (unix) for wireguard conf file
			/usr/local/bin/dos2unix.sh "${VPN_CONFIG}"

			# get endpoint line from wireguard config file
			export VPN_REMOTE_SERVER=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^Endpoint\s=\s)[^:]+' || true)
			if [[ -z "${VPN_REMOTE_SERVER}" ]]; then
				echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'Endpoint' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
				cat "${VPN_CONFIG}" && exit 1
			else
				echo "[info] VPN_REMOTE_SERVER defined as '${VPN_REMOTE_SERVER}'" | ts '%Y-%m-%d %H:%M:%.S'
			fi

			if [[ "${VPN_PROV}" == "pia" ]]; then

				# get wireguard port from pia api, as the port could change
				jq_query_wg_ports=".groups | .wg | .[] | .ports[]"
				export VPN_REMOTE_PORT=$(echo "${PIA_VPNINFO_API}" | jq -r "${jq_query_wg_ports}" 2> /dev/null)

				if [[ -z "${VPN_REMOTE_PORT}" ]]; then
					export VPN_REMOTE_PORT=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^Endpoint\s=\s).*' | grep -P -o '[\d]+$' || true)
					if [[ -z "${VPN_REMOTE_PORT}" ]]; then
						echo "[warn] VPN configuration file ${VPN_CONFIG} does not contain port on 'Endpoint' line, defaulting to '1337'" | ts '%Y-%m-%d %H:%M:%.S'
						export VPN_REMOTE_PORT="1337"
					fi
				fi

			else

				export VPN_REMOTE_PORT=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^Endpoint\s=\s).*' | grep -P -o '[\d]+$' || true)
				if [[ -z "${VPN_REMOTE_PORT}" ]]; then
					echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain port on 'Endpoint' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
					cat "${VPN_CONFIG}" && exit 1
				fi

			fi
			echo "[info] VPN_REMOTE_PORT defined as '${VPN_REMOTE_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'

		fi

		# device type (derived from the wireguard config filename without the file extesion) will always be wg0
		# as we forceably rename the file
		echo "[info] VPN_DEVICE_TYPE defined as 'wg0'" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_DEVICE_TYPE="wg0"

		# protocol for wireguard is always udp
		echo "[info] VPN_REMOTE_PROTOCOL defined as 'udp'" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_REMOTE_PROTOCOL="udp"

	elif [[ "${VPN_CLIENT}" == "openvpn" ]]; then

		# create directory to store openvpn config files
		mkdir -p /config/openvpn

		# set perms and owner for files in /config/openvpn directory
		set +e
		chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
		exit_code_chown=$?
		chmod -R 775 "/config/openvpn" &> /dev/null
		exit_code_chmod=$?
		set -e

		if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
			echo "[warn] Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		# force removal of mac os resource fork files in ovpn folder
		rm -rf /config/openvpn/._*.ovpn

		# wildcard search for openvpn config files (match on first result)
		export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

		# if ovpn file not found in /config/openvpn then exit
		if [[ -z "${VPN_CONFIG}" ]]; then
			echo "[crit] No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
		fi

		echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

		# convert CRLF (windows) to LF (unix) for ovpn
		/usr/local/bin/dos2unix.sh "${VPN_CONFIG}"

		# get all remote lines in ovpn file and save comma separated
		vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^remote\s).*' | paste -s -d, - || true)

		if [[ -n "${vpn_remote_line}" ]]; then

			# if remote servers are legacy then log issue and exit
			if [[ "${vpn_remote_line}" == *"privateinternetaccess.com"* ]]; then
				echo "[crit] VPN configuration file '${VPN_CONFIG}' 'remote' line is referencing PIA legacy network which is now shutdown, see Q19. from the following link on how to switch to PIA 'next-gen':- https://github.com/binhex/documentation/blob/master/docker/faq/vpn.md exiting script..." | ts '%Y-%m-%d %H:%M:%.S'
				exit 1
			fi

			# split comma separated string into list from vpn_remote_line variable
			IFS=',' read -ra vpn_remote_line_list <<< "${vpn_remote_line}"

			# process each remote line from ovpn file
			for vpn_remote_line_item in "${vpn_remote_line_list[@]}"; do

				# if remote line contains comments then remove
				vpn_remote_line_item=$(echo "${vpn_remote_line_item}" | sed -r 's~\s?+#.*$~~g')

				vpn_remote_server_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f1 || true)

				if [[ -z "${vpn_remote_server_cut}" ]]; then
					echo "[warn] VPN configuration file ${VPN_CONFIG} remote line is missing or malformed, skipping to next remote line..." | ts '%Y-%m-%d %H:%M:%.S'
					continue
				fi

				vpn_remote_port_cut=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^port\s).*' || true)
				if [[ -z "${vpn_remote_port_cut}" ]]; then
					vpn_remote_port_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f2 | grep -P -o '^[\d]{2,5}$' || true)
					if [[ -z "${vpn_remote_port_cut}" ]]; then
						echo "[warn] VPN confi
						guration file ${VPN_CONFIG} remote port is missing or malformed, assuming port '1194'" | ts '%Y-%m-%d %H:%M:%.S'
						vpn_remote_port_cut="1194"
					fi
				fi

				vpn_remote_protocol_cut=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^proto\s).*' || true)
				if [[ -z "${vpn_remote_protocol_cut}" ]]; then
					vpn_remote_protocol_cut=$(echo "${vpn_remote_line_item}" | cut -d " " -f3 || true)
					if [[ -z "${vpn_remote_protocol_cut}" ]]; then
						echo "[warn] VPN configuration file ${VPN_CONFIG} remote protocol is missing or malformed, assuming protocol 'udp'" | ts '%Y-%m-%d %H:%M:%.S'
						vpn_remote_protocol_cut="udp"
					fi
				fi

				if [[ "${vpn_remote_protocol_cut}" == "tcp" ]]; then
					# if remote line contains old format 'tcp' then replace with newer 'tcp-client' format
					vpn_remote_protocol_cut="tcp-client"
				fi

				vpn_remote_server+="${vpn_remote_server_cut},"
				vpn_remote_port+="${vpn_remote_port_cut},"
				vpn_remote_protocol+="${vpn_remote_protocol_cut},"

			done

			echo "[info] VPN remote server(s) defined as '${vpn_remote_server}'" | ts '%Y-%m-%d %H:%M:%.S'
			echo "[info] VPN remote port(s) defined as '${vpn_remote_port}'" | ts '%Y-%m-%d %H:%M:%.S'
			echo "[info] VPN remote protcol(s) defined as '${vpn_remote_protocol}'" | ts '%Y-%m-%d %H:%M:%.S'

			export VPN_REMOTE_SERVER="${vpn_remote_server}"
			export VPN_REMOTE_PORT="${vpn_remote_port}"
			export VPN_REMOTE_PROTOCOL="${vpn_remote_protocol}"

		else

			echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
			cat "${VPN_CONFIG}" && exit 1

		fi

		VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
			export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
			echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[crit] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
		fi

		export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_OPTIONS}" ]]; then
			echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_OPTIONS=""
		fi

	fi

	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to name servers defined in readme.md" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1"
	fi

	if [[ "${VPN_PROV}" != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi

	if [[ "${VPN_PROV}" == "pia" ]]; then

		export STRICT_PORT_FORWARD=$(echo "${STRICT_PORT_FORWARD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${STRICT_PORT_FORWARD}" ]]; then
			echo "[info] STRICT_PORT_FORWARD defined as '${STRICT_PORT_FORWARD}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRICT_PORT_FORWARD not defined (via -e STRICT_PORT_FORWARD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRICT_PORT_FORWARD="yes"
		fi

	fi

	export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

	export ADDITIONAL_PORTS=$(echo "${ADDITIONAL_PORTS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ADDITIONAL_PORTS}" ]]; then
			echo "[info] ADDITIONAL_PORTS defined as '${ADDITIONAL_PORTS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
			echo "[info] ADDITIONAL_PORTS not defined (via -e ADDITIONAL_PORTS), skipping allow for custom incoming ports" | ts '%Y-%m-%d %H:%M:%.S'
	fi

fi

EOF

# replace env vars common placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_COMMON_PLACEHOLDER/{
    s/# ENVVARS_COMMON_PLACEHOLDER//g
    r /tmp/envvars_common_heredoc
}' /usr/local/bin/init.sh
rm /tmp/envvars_common_heredoc

# cleanup
cleanup.sh
