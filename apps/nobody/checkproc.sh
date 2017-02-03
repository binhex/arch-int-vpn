#!/bin/bash

# ${1} = port number for downloader e.g. 58846
# ${2} = path to process running e.g. /usr/bin/deluged

# wait for process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".${1}"') == "" ]]; do
	sleep 0.1
done

# define location and name of pid file
pid_file="/home/nobody/downloader.sleep.pid"

# set sleep period for recheck (in secs)
sleep_period="10"

while true; do

	# check if process is running, if not then kill sleep process for downloader shell
	if ! pgrep -f "${2}" > /dev/null; then

		if [[ -f "${pid_file}" ]]; then

			echo "[warn] Downloader process terminated, killing sleep command in downloader script to force restart and refresh of ip/port..."
			pkill -P $(<"${pid_file}") sleep
			echo "[info] Sleep process killed"

			# sleep for 30 secs to give deluge chance to start before re-checking
			sleep 30s

		else

			echo "[info] No PID file containing PID for sleep command in downloader script present, assuming script hasn't started yet."

		fi

	fi

	sleep "${sleep_period}"s

done
