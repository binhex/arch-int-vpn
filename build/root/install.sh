#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# detect image arch
####

OS_ARCH=$(uname -m)
if [[ ! -z "${OS_ARCH}" ]]; then
	if [[ "${OS_ARCH}" == "x86_64" ]]; then
		OS_ARCH="x86-64"
	fi
	echo "[info] OS_ARCH defined as '${OS_ARCH}'"
else
	echo "[warn] Unable to identify OS_ARCH, defaulting to 'x86-64'"
	OS_ARCH="x86-64"
fi

# pacman packages
####

# define pacman packages
apk_packages="kmod privoxy bind-tools netcat-openbsd ipcalc wireguard-tools openresolv"

# install pre-reqs
apk add --no-cache $apk_packages

# env vars
####

cat << 'EOF' > /tmp/envvars_common_heredoc

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export VPN_ENABLED="yes"
echo "[info] VPN_ENABLED " | ts '%Y-%m-%d %H:%M:%.S'

export VPN_CLIENT="wireguard"
echo "[info] VPN_CLIENT defined as '${VPN_CLIENT}'" | ts '%Y-%m-%d %H:%M:%.S'

export VPN_PROV="custom"
echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'

if [[ "${VPN_CLIENT}" == "wireguard" ]]; then

# create directory to store wireguard config files
mkdir -p /config/wireguard

# set perms and owner for files in /config/wireguard directory
set +e
chown -R "${PUID}":"${PGID}" "/config/wireguard" &> /dev/null
exit_code_chown=$?
chmod -R 775 "/config/wireguard" &> /dev/null
set -e

# force removal of mac os resource fork files in wireguard folder
rm -rf /config/wireguard/._*.conf

# wildcard search for wireguard config files (match on first result)
vpn_config_path=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)

if [[ -z "${vpn_config_path}" ]]; then
	# if conf file not found in /config/wireguard
	echo "[crit] No WireGuard config file located in /config/wireguard/ (conf extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1

else
	# rename wireguard config file to prevent issues with spaces and other illegal characters for device
	export VPN_CONFIG="/config/wireguard/wg0.conf"
	if [[ $(basename "${vpn_config_path}") != wg0.conf ]]; then
		mv "${vpn_config_path}" "${VPN_CONFIG}"
	fi
	echo "[info] WireGuard config file (conf extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'


	# get endpoint line from wireguard config file
	export VPN_REMOTE_SERVER=$(grep -P -o '(?<=^Endpoint\s=\s)[^:]+' "${VPN_CONFIG}" || true)
	if [[ -z "${VPN_REMOTE_SERVER}" ]]; then
		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'Endpoint' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1
	else
		echo "[info] VPN_REMOTE_SERVER defined as '${VPN_REMOTE_SERVER}'" | ts '%Y-%m-%d %H:%M:%.S'
	fi


	export VPN_REMOTE_PORT=$(cat "${VPN_CONFIG}" | grep -P -o '(?<=^Endpoint\s=\s).*' | grep -P -o '[\d]+$' || true)
	if [[ -z "${VPN_REMOTE_PORT}" ]]; then
		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain port on 'Endpoint' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1
	fi

fi

echo "[info] VPN_REMOTE_PORT defined as '${VPN_REMOTE_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'

# device type (derived from the wireguard config filename without the file extesion) will always be wg0 as we forceably rename the file
echo "[info] VPN_DEVICE_TYPE defined as 'wg0'" | ts '%Y-%m-%d %H:%M:%.S'
export VPN_DEVICE_TYPE="wg0"

# protocol for wireguard is always udp
echo "[info] VPN_REMOTE_PROTOCOL defined as 'udp'" | ts '%Y-%m-%d %H:%M:%.S'
export VPN_REMOTE_PROTOCOL="udp"


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

EOF

# replace env vars common placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_COMMON_PLACEHOLDER/{
    s/# ENVVARS_COMMON_PLACEHOLDER//g
    r /tmp/envvars_common_heredoc
}' /usr/local/bin/init.sh

rm /tmp/envvars_common_heredoc

chmod 750 /usr/local/bin/init.sh
