#!/bin/bash

function cleanup_tunnel_markers() {
  # remove file that denotes tunnel is down (from openvpndown.sh)
  rm -f '/tmp/tunneldown'
}

function run_tunnel_setup() {
  # run scripts to get tunnel ip, check dns, get external ip, and get incoming port
  # note needs to be run in background, otherwise it blocks openvpn
  /root/prerunget.sh &
}

function main() {
  cleanup_tunnel_markers
  run_tunnel_setup
}

main
