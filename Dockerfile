FROM binhex/arch-base:20170510-01
MAINTAINER binhex

# additional files
##################

# add install bash script
ADD build/root/*.sh /root/

# add bash script to run openvpn
ADD build/root/*.sh /root/

# add bash script to run privoxy
ADD run/nobody/*.sh /home/nobody/

# add config files
ADD config/pia/default/* /home/nobody/certs/default/
ADD config/pia/strong/* /home/nobody/certs/strong/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh

# docker settings
#################

# expose port for privoxy
EXPOSE 8118
