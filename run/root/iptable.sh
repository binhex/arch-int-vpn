#!/bin/bash

function initialize_port_arrays() {
  # Initialize arrays for incoming ports
  local -n ext_array_ref="${1}"
  shift
  local -n lan_array_ref="${1}"
  shift

  ext_array_ref=()
  lan_array_ref=()

  # Append incoming ports for applications to arrays
  if [[ "${APPLICATION}" == "qbittorrent" ]]; then
    ext_array_ref+=("${WEBUI_PORT}")
  elif [[ "${APPLICATION}" == "sabnzbd" ]]; then
    ext_array_ref+=(8080 8090)
  elif [[ "${APPLICATION}" == "deluge" ]]; then
    ext_array_ref+=(8112)
    lan_array_ref+=(58846)
  fi

  # If microsocks enabled then add port for microsocks to incoming ports lan array
  if [[ "${ENABLE_SOCKS}" == "yes" ]]; then
    lan_array_ref+=(9118)
  fi

  # If privoxy enabled then add port for privoxy to incoming ports lan array
  if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then
    lan_array_ref+=(8118)
  fi
}

function setup_port_arrays() {
  # shellcheck disable=SC2034  # incoming_ports_lan_array_ref used via nameref
  local -n incoming_ports_ext_array_ref="${1}"
  shift
  # shellcheck disable=SC2034  # incoming_ports_lan_array_ref used via nameref
  local -n incoming_ports_lan_array_ref="${1}"
  shift
  # shellcheck disable=SC2034  # outgoing_ports_lan_array_ref used via nameref
  local -n outgoing_ports_lan_array_ref="${1}"
  shift
  # shellcheck disable=SC2034  # vpn_input_ports_array_ref used via nameref
  local -n vpn_input_ports_array_ref="${1}"
  shift

  # Initialize port arrays
  initialize_port_arrays incoming_ports_ext_array_ref incoming_ports_lan_array_ref

  # if vpn input ports specified then add to incoming ports external array
  if [[ -n "${VPN_INPUT_PORTS}" ]]; then
    # split comma separated string into array from VPN_INPUT_PORTS env variable
    IFS=',' read -ra vpn_input_ports_array_ref <<< "${VPN_INPUT_PORTS}"
    # merge both arrays
    incoming_ports_ext_array_ref=("${incoming_ports_ext_array_ref[@]}" "${vpn_input_ports_array_ref[@]}")
  fi

  # if vpn output ports specified then add to outbound ports lan array
  if [[ -n "${VPN_OUTPUT_PORTS}" ]]; then
    # split comma separated string into array from VPN_OUTPUT_PORTS env variable
    # shellcheck disable=SC2034  # outgoing_ports_lan_array_ref used via nameref
    IFS=',' read -ra outgoing_ports_lan_array_ref <<< "${VPN_OUTPUT_PORTS}"
  fi
}

function setup_network_arrays() {
  # shellcheck disable=SC2034  # vpn_remote_ip_array_ref used via nameref
  local -n vpn_remote_ip_array_ref="${1}"
  shift
  # shellcheck disable=SC2034  # lan_network_array_ref used via nameref
  local -n lan_network_array_ref="${1}"
  shift
  # shellcheck disable=SC2034  # multi_protocol_array_ref used via nameref
  local -n multi_protocol_array_ref="${1}"
  shift

  # convert list of ip's back into an array (cannot export arrays in bash)
  # shellcheck disable=SC2034  # vpn_remote_ip_array_ref used via nameref
  IFS=' ' read -ra vpn_remote_ip_array_ref <<< "${VPN_REMOTE_IP_LIST}"

  # array for both protocols
  # shellcheck disable=SC2034  # multi_protocol_array_ref used via nameref
  multi_protocol_array_ref=(tcp udp)

  # split comma separated string into array from LAN_NETWORK env variable
  # shellcheck disable=SC2034  # lan_network_array_ref used via nameref
  IFS=',' read -ra lan_network_array_ref <<< "${LAN_NETWORK}"
}

function setup_ip_routes() {
  local -a lan_network_array=("$@")
  local lan_network_item
  local default_gateway_adapter
  local default_gateway_ip

  # process lan networks in the array
  for lan_network_item in "${lan_network_array[@]}"; do
    # strip whitespace from start and end of lan_network_item
    lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    # read in DOCKER_NETWORKING from tools.sh, get 2nd and third values in first list item
    default_gateway_adapter="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 2 )"
    default_gateway_ip="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 3 )"

    echo "[info] Adding ${lan_network_item} as route via adapter ${default_gateway_adapter}"
    ip route add "${lan_network_item}" via "${default_gateway_ip}" dev "${default_gateway_adapter}"
  done

  echo "[info] ip route defined as follows..."
  echo "--------------------"
  ip route s t all
  echo "--------------------"
}

function setup_iptables_marks() {
  local -a incoming_ports_ext_array=("$@")
  local iptable_mangle_exit_code
  local mark
  local incoming_ports_ext_item
  local default_gateway_ip

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

    # read in DOCKER_NETWORKING from tools.sh, get third value in first list item
    default_gateway_ip="$(echo "${DOCKER_NETWORKING}" | cut -d ',' -f 3 )"

    # setup route for application using set-mark to route traffic to lan
    for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do
      mark=$((mark+1))
      echo "${incoming_ports_ext_item}    ${incoming_ports_ext_item}_${APPLICATION}" >> '/etc/iproute2/rt_tables'
      ip rule add fwmark "${mark}" table "${incoming_ports_ext_item}_${APPLICATION}"
      ip route add default via "${default_gateway_ip}" table "${incoming_ports_ext_item}_${APPLICATION}"
    done
  fi

  # Return the exit code for use in other functions
  echo "${iptable_mangle_exit_code}"
}

function setup_input_docker_rules() {
  local -a vpn_remote_ip_array=("$@")
  local docker_network
  local docker_interface
  local docker_network_cidr
  local vpn_remote_ip_item
  local rule_exists

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
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
}

function setup_input_port_rules() {
  local -a incoming_ports_ext_array=("$@")
  local docker_network
  local docker_interface
  local incoming_ports_ext_item
  local vpn_remote_protocol_item
  local multi_protocol_array=(tcp udp)

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

    for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

      for vpn_remote_protocol_item in "${multi_protocol_array[@]}"; do

        # allows communication from any ip (ext or lan) to containers running in vpn network on specific ports
        iptables -A INPUT -i "${docker_interface}" -p "${vpn_remote_protocol_item}" --dport "${incoming_ports_ext_item}" -j ACCEPT

      done

    done

  done
}

function setup_input_lan_rules() {
  local -a lan_network_array=("${!1}")
  local -a incoming_ports_lan_array=("${!2}")
  local -a outgoing_ports_lan_array=("${!3}")
  local docker_network
  local docker_interface
  local docker_network_cidr
  local lan_network_item
  local incoming_ports_lan_item
  local outgoing_ports_lan_item

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
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
}

function setup_input_misc_rules() {
  # accept input icmp (ping)
  iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

  # accept input to local loopback
  iptables -A INPUT -i lo -j ACCEPT

  # accept input to tunnel adapter
  iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT
}

function setup_output_docker_rules() {
  local -a vpn_remote_ip_array=("$@")
  local docker_network
  local docker_interface
  local docker_network_cidr
  local vpn_remote_ip_item
  local rule_exists

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
    docker_network_cidr="$(echo "${docker_network}" | cut -d ',' -f 6 )"

    # accept output to/from docker containers (172.x range is internal dhcp)
    iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

  done

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
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
}

function setup_output_mangle_rules() {
  local iptable_mangle_exit_code="${1}"
  shift
  local -a incoming_ports_ext_array=("$@")
  local mark
  local incoming_ports_ext_item

  # if iptable mangle is available (kernel module) then use mark
  if [[ "${iptable_mangle_exit_code}" == 0 ]]; then

    mark=0

    for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

      mark=$((mark+1))
      # accept output from application - used for external access
      iptables -t mangle -A OUTPUT -p tcp --sport "${incoming_ports_ext_item}" -j MARK --set-mark "${mark}"

    done

  fi
}

function setup_output_port_rules() {
  local -a incoming_ports_ext_array=("$@")
  local docker_network
  local docker_interface
  local incoming_ports_ext_item
  local vpn_remote_protocol_item
  local multi_protocol_array=(tcp udp)

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
    docker_interface="$(echo "${docker_network}" | cut -d ',' -f 1 )"

    for incoming_ports_ext_item in "${incoming_ports_ext_array[@]}"; do

      for vpn_remote_protocol_item in "${multi_protocol_array[@]}"; do

        # return rule
        iptables -A OUTPUT -o "${docker_interface}" -p "${vpn_remote_protocol_item}" --sport "${incoming_ports_ext_item}" -j ACCEPT

      done

    done

  done
}

function setup_output_lan_rules() {
  local -a lan_network_array=("${!1}")
  local -a incoming_ports_lan_array=("${!2}")
  local -a outgoing_ports_lan_array=("${!3}")
  local docker_network
  local docker_interface
  local docker_network_cidr
  local lan_network_item
  local incoming_ports_lan_item
  local outgoing_ports_lan_item

  # loop over docker adapters
  for docker_network in ${DOCKER_NETWORKING}; do

    # read in DOCKER_NETWORKING from tools.sh
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
}

function setup_output_misc_rules() {
  # accept output for icmp (ping)
  iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

  # accept output from local loopback adapter
  iptables -A OUTPUT -o lo -j ACCEPT

  # accept output from tunnel adapter
  iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT
}

function print_iptables_summary() {
  echo "[info] iptables defined as follows..."
  echo "--------------------"
  iptables -S 2>&1 | tee /tmp/getiptables
  chmod +r /tmp/getiptables
  echo "--------------------"
}

function main() {
  # source in tools script
  # shellcheck source=../local/tools.sh
  source tools.sh

  # run function from tools.sh, this creates global var 'docker_networking' used below
  get_docker_networking

  # Declare arrays that will be used throughout the script
  local incoming_ports_ext_array=()
  local incoming_ports_lan_array=()
  local outgoing_ports_lan_array=()
  # shellcheck disable=SC2034  # vpn_input_ports_array passed to functions via reference
  local vpn_input_ports_array=()
  local vpn_remote_ip_array=()
  local lan_network_array=()
  local multi_protocol_array=()

  # Setup all the arrays
  setup_port_arrays incoming_ports_ext_array incoming_ports_lan_array outgoing_ports_lan_array vpn_input_ports_array
  setup_network_arrays vpn_remote_ip_array lan_network_array multi_protocol_array

  # Setup IP routes
  setup_ip_routes "${lan_network_array[@]}"

  # Setup iptables marks and get the exit code
  local iptable_mangle_exit_code
  iptable_mangle_exit_code=$(setup_iptables_marks "${incoming_ports_ext_array[@]}")

  # Setup input iptables rules
  setup_input_docker_rules "${vpn_remote_ip_array[@]}"
  setup_input_port_rules "${incoming_ports_ext_array[@]}"
  setup_input_lan_rules lan_network_array[@] incoming_ports_lan_array[@] outgoing_ports_lan_array[@]
  setup_input_misc_rules

  # Setup output iptables rules
  setup_output_docker_rules "${vpn_remote_ip_array[@]}"
  setup_output_mangle_rules "${iptable_mangle_exit_code}" "${incoming_ports_ext_array[@]}"
  setup_output_port_rules "${incoming_ports_ext_array[@]}"
  setup_output_lan_rules lan_network_array[@] incoming_ports_lan_array[@] outgoing_ports_lan_array[@]
  setup_output_misc_rules

  # Print summary of iptables rules
  print_iptables_summary
}

# Run the main function
main "$@"
