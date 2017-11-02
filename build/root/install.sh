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

# pacman packages
####

# define pacman packages
pacman_packages="kmod openvpn privoxy dnsutils"

# install pre-reqs
pacman -S --needed $pacman_packages --noconfirm

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
