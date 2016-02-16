FROM binhex/arch-base:latest
MAINTAINER binhex

# additional files
##################

# add install bash script
ADD setup/root/*.sh /root/

# add bash script to run openvpn
ADD apps/root/*.sh /root/

# add bash script to run privoxy
ADD apps/nobody/*.sh /home/nobody/

# add pia certificates and sample openvpn.ovpn file
ADD config/pia/* /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh

# docker settings
#################

# expose port for privoxy
EXPOSE 8118
