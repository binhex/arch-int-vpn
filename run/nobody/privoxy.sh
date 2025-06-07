#!/usr/bin/dumb-init /bin/bash
# shellcheck shell=bash

function setup_privoxy_config() {
  mkdir -p /config/privoxy

  if [[ ! -f "/config/privoxy/config" ]]; then

    echo "[info] Configuring Privoxy..."
    cp -R /etc/privoxy/ /config/

    sed -i -e "s~confdir /etc/privoxy~confdir /config/privoxy~g" /config/privoxy/config
    sed -i -e "s~logdir /var/log/privoxy~logdir /config/privoxy~g" /config/privoxy/config
    sed -i -e "s~listen-address.*~listen-address :8118~g" /config/privoxy/config

  fi
}

function wait_for_privoxy_process() {
  local retry_count=12
  local retry_wait=1

  while true; do

    if ! pgrep -x "privoxy" > /dev/null; then

      retry_count=$((retry_count-1))
      if [ "${retry_count}" -eq "0" ]; then

        echo "[warn] Wait for Privoxy process to start aborted, too many retries"
        echo "[info] Showing output from command before exit..."
        timeout 10 /usr/bin/privoxy /config/privoxy/config ; return 1

      else

        if [[ "${DEBUG}" == "true" ]]; then
          echo "[debug] Waiting for Privoxy process to start"
          echo "[debug] Re-check in ${retry_wait} secs..."
          echo "[debug] ${retry_count} retries left"
        fi
        sleep "${retry_wait}s"

      fi

    else

      echo "[info] Privoxy process started"
      break

    fi

  done
}

function wait_for_privoxy_port() {
  echo "[info] Waiting for Privoxy process to start listening on port 8118..."

  while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".8118\"") == "" ]]; do
    sleep 0.1
  done

  echo "[info] Privoxy process listening on port 8118"
}

function start_privoxy() {
  if ! pgrep -x "privoxy" > /dev/null; then

    echo "[info] Attempting to start Privoxy..."

    # run Privoxy (daemonized, non-blocking)
    /usr/bin/privoxy /config/privoxy/config

    # make sure process privoxy DOES exist
    wait_for_privoxy_process
    wait_for_privoxy_port

  fi
}

function configure_privoxy() {
  if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

    setup_privoxy_config
    start_privoxy

  else

    if [[ "${DEBUG}" == "true" ]]; then
      echo "[info] Privoxy set to disabled"
    fi

  fi

  # set privoxy ip to current vpn ip (used when checking for changes on next run)
  local vpn_ip
  vpn_ip=$(</tmp/getvpnip)
  # shellcheck disable=SC2034  # privoxy_ip may be used for tracking state changes
  local privoxy_ip="${vpn_ip}"
}

function main() {
  configure_privoxy
}

main
