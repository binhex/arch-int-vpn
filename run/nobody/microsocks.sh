#!/usr/bin/dumb-init /bin/bash

function start_microsocks() {
  echo "[info] Attempting to start microsocks..."

  local microsocks_cli="nohup /usr/local/bin/microsocks -i 0.0.0.0 -p 9118"

  if [[ -n "${SOCKS_USER}" ]]; then
    microsocks_cli="${microsocks_cli} -u ${SOCKS_USER} -P ${SOCKS_PASS}"
  fi

  if [[ "${VPN_ENABLED}" == "yes" ]]; then
    microsocks_cli="${microsocks_cli} -b ${VPN_IP}"
  fi

  if [[ "${DEBUG}" == "false" ]]; then
    microsocks_cli="${microsocks_cli} -q"
  fi

  ${microsocks_cli} &

  echo "[info] microsocks process started"
}

function main() {
  start_microsocks
}

main "$@"
