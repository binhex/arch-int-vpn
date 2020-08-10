#!/bin/bash

# script to call multiple scripts in series to read and then write out values

# blocking script, will wait for valid ip address assigned to tun0/tap0 (port written to file /tmp/getvpnip)
source /root/getvpnip.sh

# blocking script, will wait for vpn incoming port to be assigned (port written to file /tmp/getvpnport)
source /root/getvpnport.sh

# blocking script, will wait for external ip address retrieval (external ip written to file /tmp/getvpnextip)
source /root/getvpnextip.sh
