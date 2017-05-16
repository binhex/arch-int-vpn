#!/bin/bash

# run scripts to get port and external ip as seperate background shell processes (prevents blocking)
/bin/bash /root/getvpnport.sh &
/bin/bash /root/getvpnextip.sh &
