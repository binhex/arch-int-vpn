#!/bin/bash

# script to call multiple scripts in series to read and then write out values

# blocking script, will wait for valid ip address assigned to tun0/tap0
source /home/nobody/getvpnip.sh

# blocking script, will wait for valid vpn incoming port and write value out (if provider is pia)
# writes value to file '/home/nobody/vpn_incoming_port.txt'
source /root/getvpnport.sh

# blocking script, will wait for names to resolve (required for /root/getvpnextip.sh)
source /root/checkdns.sh

# blocking script, will wait for vpn external ip address to be retrieved and write value out (via ns or web lookup)
# writes value to file '/home/nobody/vpn_external_ip.txt'
source /root/getvpnextip.sh
