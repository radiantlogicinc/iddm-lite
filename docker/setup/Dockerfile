FROM debian:12.9-slim

RUN apt update && \
    apt install openssl jq libxml2-utils xmlstarlet unzip curl xxd netcat-traditional -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

COPY ./fid-setup.sh /fid-setup.sh
RUN chmod +x /fid-setup.sh

ENTRYPOINT [ "/fid-setup.sh" ]