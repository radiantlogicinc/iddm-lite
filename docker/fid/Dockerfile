ARG IDDM_VERSION='8.1.5-rc.1'

FROM radiantone/fid-nightly:$IDDM_VERSION

COPY ./homedepot-start.sh /opt/radiantone/homedepot-start.sh
RUN chmod +x /opt/radiantone/homedepot-start.sh

ENTRYPOINT [ "/opt/radiantone/homedepot-start.sh" ]