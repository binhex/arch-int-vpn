#!/usr/bin/dumb-init /bin/bash

# run scripts to get tunnel ip, check dns, get external ip, and get incoming port
# note needs to be run in background, otherwise it blocks openvpn
/root/prerunget.sh &
