#!/bin/bash

# script to call multiple scripts in series to read and then write out values

function source_tools() {
  # source in various tools
  source tools.sh
}

function setup_vpn_gateway() {
  # blocking function, will wait for valid ip address assigned to tun0/tap0 (port written to file /tmp/getvpnip)
  get_vpn_gateway_ip
}

function verify_dns() {
  # blocking function, will wait for name resolution to be operational (will write to /tmp/dnsfailure if failure)
  check_dns www.google.com
}

function get_external_ip() {
  # blocking function, will wait for external ip address retrieval (external ip written to file /tmp/getvpnextip)
  get_vpn_external_ip
}

function setup_port_forwarding() {
  # pia|protonvpn only - backgrounded function, will wait for vpn incoming port to be assigned (port written to file /tmp/getvpnport)
  # note backgrounded as running in infinite loop to check for port assignment
  get_vpn_incoming_port &
}

function main() {
  source_tools
  setup_vpn_gateway
  verify_dns
  get_external_ip
  setup_port_forwarding
}

main
