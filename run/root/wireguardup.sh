#!/bin/bash

# remove file that denotes tunnel is down (from wireguarddown.sh)
rm -f '/tmp/tunneldown'

# run scripts to get tunnel ip, check dns, get external ip, and get incoming port
# note do not background this script, otherwise you cannot kill the backgrounded
# tools.sh/get_vpn_incoming_port function
/root/prerunget.sh
