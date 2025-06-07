#!/usr/bin/dumb-init /bin/bash
# shellcheck shell=bash

function build_microsocks_cli() {

  local microsocks_cli="nohup /usr/local/bin/microsocks -i 0.0.0.0 -p 9118"

  if [[ -n "${SOCKS_USER}" ]]; then
    microsocks_cli="${microsocks_cli} -u ${SOCKS_USER} -P ${SOCKS_PASS}"
  fi

  if [[ "${VPN_ENABLED}" == "yes" ]]; then
    local vpn_ip
    vpn_ip=$(</tmp/getvpnip)
    microsocks_cli="${microsocks_cli} -b ${vpn_ip}"
  fi

  if [[ "${DEBUG}" == "false" ]]; then
    microsocks_cli="${microsocks_cli} -q"
  fi

  echo "${microsocks_cli}"
}

function start_microsocks() {

  local microsocks_cli

  echo "[info] Attempting to start microsocks..."

  microsocks_cli=$(build_microsocks_cli)

  ${microsocks_cli} &

  echo "[info] microsocks process started"
}

function main() {
  start_microsocks
}

main
