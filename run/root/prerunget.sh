#!/bin/bash

# script to call multiple scripts in series to read and then write out values

# source in various tools
source tools.sh

# blocking function, will wait for valid ip address assigned to tun0/tap0 (port written to file /tmp/getvpnip)
get_vpn_gateway_ip

# blocking function, will wait for name resolution to be operational (will write to /tmp/dnsfailure if failure)
check_dns www.google.com

# blocking function, will wait for external ip address retrieval (external ip written to file /tmp/getvpnextip)
get_vpn_external_ip

# pia|protonvpn only - backgrounded function, will wait for vpn incoming port to be assigned (port written to file /tmp/getvpnport)
# note backgrounded as running in infinite loop to check for port assignment
get_vpn_incoming_port &
