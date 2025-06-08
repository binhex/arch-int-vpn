#!/bin/bash

function setup_port_arrays() {
  # initialise arrays for incoming ports
  declare -ga INCOMING_PORTS_EXT_ARRAY=()
  declare -ga INCOMING_PORTS_LAN_ARRAY=()

  # append incoming ports for applications to arrays
  if [[ "${APPLICATION}" == "qbittorrent" ]]; then
    INCOMING_PORTS_EXT_ARRAY+=("${WEBUI_PORT}")
  elif [[ "${APPLICATION}" == "sabnzbd" ]]; then
    INCOMING_PORTS_EXT_ARRAY+=(8080 8090)
  elif [[ "${APPLICATION}" == "deluge" ]]; then
    INCOMING_PORTS_EXT_ARRAY+=(8112)
    INCOMING_PORTS_LAN_ARRAY+=(58846)
  fi

  # if microsocks enabled then add port for microsocks to incoming ports lan array
  if [[ "${ENABLE_SOCKS}" == "yes" ]]; then
    INCOMING_PORTS_LAN_ARRAY+=(9118)
  fi

  # if privoxy enabled then add port for privoxy to incoming ports lan array
  if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then
    INCOMING_PORTS_LAN_ARRAY+=(8118)
  fi

  # if vpn input ports specified then add to incoming ports external array
  if [[ -n "${VPN_INPUT_PORTS}" ]]; then
    # split comma separated string into array from VPN_INPUT_PORTS env variable
    local -a vpn_input_ports_array
    IFS=',' read -ra vpn_input_ports_array <<< "${VPN_INPUT_PORTS}"

    # merge both arrays
    INCOMING_PORTS_EXT_ARRAY+=("${vpn_input_ports_array[@]}")
  fi
}

function setup_ip_arrays() {
  # convert list of ip's back into an array (cannot export arrays in bash)
  declare -ga VPN_REMOTE_IP_ARRAY
  IFS=' ' read -ra VPN_REMOTE_IP_ARRAY <<< "${VPN_REMOTE_IP_LIST}"

  # if vpn output ports specified then add to outbound ports lan array
  if [[ -n "${VPN_OUTPUT_PORTS}" ]]; then
    # split comma separated string into array from VPN_OUTPUT_PORTS env variable
    declare -ga OUTGOING_PORTS_LAN_ARRAY
    IFS=',' read -ra OUTGOING_PORTS_LAN_ARRAY <<< "${VPN_OUTPUT_PORTS}"
  fi
}

function setup_main_arrays() {
  # source in tools script
  # shellcheck source=../local/tools.sh
  source tools.sh

  # run function from tools.sh, this creates global var 'DOCKER_NETWORKING' used below
  get_docker_networking

  # array for both protocols
  declare -ga MULTI_PROTOCOL_ARRAY=(tcp udp)

  # split comma separated string into array from LAN_NETWORK env variable
  declare -ga LAN_NETWORK_ARRAY
  IFS=',' read -ra LAN_NETWORK_ARRAY <<< "${LAN_NETWORK}"

  # split comma separated string into array from VPN_REMOTE_PORT env var
  declare -ga VPN_REMOTE_PORT_ARRAY
  IFS=',' read -ra VPN_REMOTE_PORT_ARRAY <<< "${VPN_REMOTE_PORT}"
}

# ip route
###

function setup_ip_routes() {
  # read in DOCKER_NETWORKING from tools.sh, get 2nd and third values in first list item
  local default_gateway_adapter
  local default_gateway_ip
  default_gateway_adapter="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 2 )"
  default_gateway_ip="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 3 )"

  # process lan networks in the array
  local lan_network_item
  for lan_network_item in "${LAN_NETWORK_ARRAY[@]}"; do
    # strip whitespace from start and end of lan_network_item
    lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    echo "[info] Adding ${lan_network_item} as route via adapter ${default_gateway_adapter}"
    ip route add "${lan_network_item}" via "${default_gateway_ip}" dev "${default_gateway_adapter}"
  done

  echo "[info] ip route defined as follows..."
  echo "--------------------"
  ip route s t all
  echo "--------------------"
}

function setup_iptables_marks() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo "[debug] Modules currently loaded for kernel" ; lsmod
  fi

  # check we have iptable_mangle, if so setup fwmark
  lsmod | grep iptable_mangle
  local iptable_mangle_exit_code="${?}"

  if [[ "${iptable_mangle_exit_code}" == 0 ]]; then
    echo "[info] iptable_mangle support detected, adding fwmark for tables"

    local mark=0
    # required as path did not exist in latest tarball (20/09/2023)
    mkdir -p '/etc/iproute2'

    # read in DOCKER_NETWORKING from tools.sh, get 2nd and third values in first list item
    local default_gateway_ip
    default_gateway_ip="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 3 )"

    # setup route for application using set-mark to route traffic to lan
    local incoming_ports_ext_item
    for incoming_ports_ext_item in "${INCOMING_PORTS_EXT_ARRAY[@]}"; do
      mark=$((mark+1))
      echo "${incoming_ports_ext_item}    ${incoming_ports_ext_item}_${APPLICATION}" >> '/etc/iproute2/rt_tables'
      ip rule add fwmark "${mark}" table "${incoming_ports_ext_item}_${APPLICATION}"
      ip route add default via "${default_gateway_ip}" table "${incoming_ports_ext_item}_${APPLICATION}"
    done
  fi
}

function setup_input_iptables() {
  # loop over docker adapters
  local docker_network
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    local docker_network_cidr
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
    docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

    # accept input to/from docker containers (172.x range is internal dhcp)
    iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

    local vpn_remote_ip_item
    for vpn_remote_ip_item in "${VPN_REMOTE_IP_ARRAY[@]}"; do
      # note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
      local rule_exists
      rule_exists=$(iptables -S | grep -e "-A INPUT -i ${docker_interface} -s ${vpn_remote_ip_item} -j ACCEPT")

      if [[ -z "${rule_exists}" ]]; then
        # return rule
        iptables -A INPUT -i "${docker_interface}" -s "${vpn_remote_ip_item}" -j ACCEPT
      fi
    done
  done

  # loop over docker adapters for incoming ports external
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

    local incoming_ports_ext_item
    for incoming_ports_ext_item in "${INCOMING_PORTS_EXT_ARRAY[@]}"; do
      local vpn_remote_protocol_item
      for vpn_remote_protocol_item in "${MULTI_PROTOCOL_ARRAY[@]}"; do
        # allows communication from any ip (ext or lan) to containers running in vpn network on specific ports
        iptables -A INPUT -i "${docker_interface}" -p "${vpn_remote_protocol_item}" --dport "${incoming_ports_ext_item}" -j ACCEPT
      done
    done
  done

  # loop over docker adapters for LAN networks
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    local docker_network_cidr
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
    docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

    # process lan networks in the array
    local lan_network_item
    for lan_network_item in "${LAN_NETWORK_ARRAY[@]}"; do
      # strip whitespace from start and end of lan_network_item
      lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

      local incoming_ports_lan_item
      for incoming_ports_lan_item in "${INCOMING_PORTS_LAN_ARRAY[@]}"; do
        # allows communication from lan ip to containers running in vpn network on specific ports
        iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -d "${docker_network_cidr}" -p tcp --dport "${incoming_ports_lan_item}" -j ACCEPT
      done

      if [[ -n "${VPN_OUTPUT_PORTS}" ]]; then
        local outgoing_ports_lan_item
        for outgoing_ports_lan_item in "${OUTGOING_PORTS_LAN_ARRAY[@]}"; do
          # return rule
          iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -d "${docker_network_cidr}" -p tcp --sport "${outgoing_ports_lan_item}" -j ACCEPT
        done
      fi
    done
  done

  # accept input icmp (ping)
  iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

  # accept input to local loopback
  iptables -A INPUT -i lo -j ACCEPT

  # accept input to tunnel adapter
  iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT
}

function setup_output_iptables() {
  # loop over docker adapters
  local docker_network
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_network_cidr
    docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

    # accept output to/from docker containers (172.x range is internal dhcp)
    iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT
  done

  # loop over docker adapters for VPN remote IPs
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

    # iterate over remote ip address array (from start.sh) and create accept rules
    local vpn_remote_ip_item
    for vpn_remote_ip_item in "${VPN_REMOTE_IP_ARRAY[@]}"; do
      # note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
      local rule_exists
      rule_exists=$(iptables -S | grep -e "-A OUTPUT -o ${docker_interface} -d ${vpn_remote_ip_item} -j ACCEPT")

      if [[ -z "${rule_exists}" ]]; then
        # accept output to remote vpn endpoint
        iptables -A OUTPUT -o "${docker_interface}" -d "${vpn_remote_ip_item}" -j ACCEPT
      fi
    done
  done

  # if iptable mangle is available (kernel module) then use mark
  lsmod | grep iptable_mangle
  local iptable_mangle_exit_code="${?}"
  if [[ "${iptable_mangle_exit_code}" == 0 ]]; then
    local mark=0
    local incoming_ports_ext_item
    for incoming_ports_ext_item in "${INCOMING_PORTS_EXT_ARRAY[@]}"; do
      mark=$((mark+1))
      # accept output from application - used for external access
      iptables -t mangle -A OUTPUT -p tcp --sport "${incoming_ports_ext_item}" -j MARK --set-mark "${mark}"
    done
  fi

  # loop over docker adapters for external ports
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

    local incoming_ports_ext_item
    for incoming_ports_ext_item in "${INCOMING_PORTS_EXT_ARRAY[@]}"; do
      local vpn_remote_protocol_item
      for vpn_remote_protocol_item in "${MULTI_PROTOCOL_ARRAY[@]}"; do
        # return rule
        iptables -A OUTPUT -o "${docker_interface}" -p "${vpn_remote_protocol_item}" --sport "${incoming_ports_ext_item}" -j ACCEPT
      done
    done
  done

  # loop over docker adapters for LAN networks
  for docker_network in ${DOCKER_NETWORKING}; do
    # read in DOCKER_NETWORKING from tools.sh
    local docker_interface
    local docker_network_cidr
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"
    docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

    # process lan networks in the array
    local lan_network_item
    for lan_network_item in "${LAN_NETWORK_ARRAY[@]}"; do
      # strip whitespace from start and end of lan_network_item
      lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

      local incoming_ports_lan_item
      for incoming_ports_lan_item in "${INCOMING_PORTS_LAN_ARRAY[@]}"; do
        # return rule
        iptables -A OUTPUT -o "${docker_interface}" -s "${docker_network_cidr}" -d "${lan_network_item}" -p tcp --sport "${incoming_ports_lan_item}" -j ACCEPT
      done

      if [[ -n "${VPN_OUTPUT_PORTS}" ]]; then
        local outgoing_ports_lan_item
        for outgoing_ports_lan_item in "${OUTGOING_PORTS_LAN_ARRAY[@]}"; do
          # allows communication from vpn network to containers running in lan network on specific ports
          iptables -A OUTPUT -o "${docker_interface}" -s "${docker_network_cidr}" -d "${lan_network_item}" -p tcp --dport "${outgoing_ports_lan_item}" -j ACCEPT
        done
      fi
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
}

function main() {
  setup_port_arrays
  setup_ip_arrays
  setup_main_arrays
  setup_ip_routes
  setup_iptables_marks
  setup_input_iptables
  setup_output_iptables
}

main "$@"
