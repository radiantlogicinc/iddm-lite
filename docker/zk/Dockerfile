ARG ZOOKEEPER_VERSION

FROM radiantone/zookeeper:$ZOOKEEPER_VERSION

HEALTHCHECK --interval=2s --timeout=30s --retries=3 \
  CMD curl -f http://localhost:8080/commands/ruok

EXPOSE 2181 2888 3888 8080 9095

ENTRYPOINT [ "/opt/radiantone/run.sh" ]