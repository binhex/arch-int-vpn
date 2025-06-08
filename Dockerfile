FROM binhex/arch-base:latest
LABEL org.opencontainers.image.authors="binhex"
LABEL org.opencontainers.image.source="https://github.com/binhex/arch-int-vpn"

# release tag name from buildx arg
ARG RELEASETAG

# arch from buildx --platform, e.g. amd64
ARG TARGETARCH

# additional files
##################

# add install bash script
ADD build/root/*.sh /root/

# add bash script for root user
ADD run/root/*.sh /root/

# add bash script for nobody user
ADD run/nobody/*.sh /home/nobody/

# add bash script for local user
ADD run/local/*.sh /usr/local/bin/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh /usr/local/bin/*.sh && \
	/bin/bash /root/install.sh "${RELEASETAG}" "${TARGETARCH}"
