FROM alpine-base-vpn:1
MAINTAINER climent

# additional files
##################

# add install bash script
ADD build/root/install.sh /root/

# add bash script to run openvpn
ADD run/root/*.sh /root/

# add bash script to run privoxy
ADD run/nobody/*.sh /home/nobody/

# add init and cleanup scripts
ADD build/root/init.sh /usr/local/bin

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
  /bin/bash /root/install.sh

# docker settings
#################

# expose port for privoxy
EXPOSE 8118
