#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /root/

# archive packages
####

# define archive packages
# note - the below installs a specific version of dig, required for synology
# boxes which seem to crash out with the following message on the latest 
# version of bind-tools (v9.13.0):-
# random.c:102: fatal error: RUNTIME_CHECK(ret >= 0) failed

arc_packages="bind-tools~9.12.1-1-x86_64"

# call arc script (arch archive repo)
source /root/arc.sh

# pacman packages
####

# define pacman packages
pacman_packages="kmod openvpn privoxy"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
