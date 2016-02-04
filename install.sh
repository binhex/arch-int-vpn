#!/bin/bash

# exit script if return code != 0
set -e

# define pacman packages
pacman_packages="kmod net-tools openvpn privoxy"

# install pre-reqs
pacman -Syu --ignore filesystem --noconfirm
pacman -S --needed $pacman_packages --noconfirm

# set permissions
chown -R nobody:users /home/nobody /usr/bin/privoxy /etc/privoxy
chmod -R 775 /home/nobody /usr/bin/privoxy /etc/privoxy

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
