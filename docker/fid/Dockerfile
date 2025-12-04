ARG IDDM_VERSION

FROM radiantone/fid:$IDDM_VERSION

COPY ./fid-start.sh /opt/radiantone/fid-start.sh
RUN chmod +x /opt/radiantone/fid-start.sh

ENTRYPOINT [ "/opt/radiantone/fid-start.sh" ]