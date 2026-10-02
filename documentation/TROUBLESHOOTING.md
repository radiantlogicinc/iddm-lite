# Troubleshooting

## Setup Debug Logging

`./run.sh setup --debug` prints the setup tool's own `[DEBUG]` lines. See
[Configuring IDDM Lite Using the Setup Image](./CONFIGURING_IDDM_LITE_SETUP_IMAGE.md) for the details.

## VDS Server Debug Logging During Setup

With `--debug`, setup raises the VDS Server log level to `DEBUG` once FID is ready, and restores the previous level when
it ends.

## Changing the VDS Server Log Level by Hand

Read the current level:

```bash
docker exec fid /opt/radiantone/vds/bin/vdsconfig.sh get-logging-property -path zk:log4j2-vds.json -key server.log.level
```

Set the level to `DEBUG`:

```bash
docker exec fid /opt/radiantone/vds/bin/vdsconfig.sh set-logging-property -path zk:log4j2-vds.json -key server.log.level -value DEBUG
```

Set it back to `WARN` the same way:

```bash
docker exec fid /opt/radiantone/vds/bin/vdsconfig.sh set-logging-property -path zk:log4j2-vds.json -key server.log.level -value WARN
```

The change applies without a restart, and it persists until it is changed again.

### Valid Levels

`OFF`, `FATAL`, `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`.

## Where the Log Is

The VDS Server log is `/opt/radiantone/vds/vds_server/logs/vds_server.log` in the `fid` container. Confirm the path
with:

```bash
docker exec fid /opt/radiantone/vds/bin/vdsconfig.sh get-logging-property -path zk:log4j2-vds.json -key server.log.file
```

View it with `docker exec fid tail -f <path>`.
