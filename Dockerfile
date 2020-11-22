FROM alpine-base-vpn:1
MAINTAINER climent

# additional files
##################

# add install bash script
ADD build/root/install.sh /root/

# add bash script to run privoxy
ADD run/nobody/*.sh /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
  /bin/bash /root/install.sh
