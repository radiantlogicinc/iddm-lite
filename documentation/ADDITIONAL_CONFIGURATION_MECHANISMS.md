# Additional Configuration Mechanisms for IDDM Lite

This page covers common additional operations you may need to perform on IDDM Lite, alongside the setup image. They are
not an alternative to the setup image. Other options exist beyond this page. For those, see the Radiant Logic
documentation or contact Radiant Logic support.

## No UI and No Configuration APIs

IDDM Lite is designed to operate under extraordinarily stringent resource constraints, most notably a cap of 4GB of
RAM. Because of this, the UI and Configuration APIs are not available in this deployment. Running IDDM with all of its
features available requires a minimum of 8GB of RAM.

## VDSConfig

The VDSConfig utility is a CLI based tool for configuring IDDM. It is an older part of the product. It is still fully
functional, but it may not support all the latest features, because all functionality is being migrated to the new
Configuration APIs.

To run vdsconfig on the in-store server, use the docker cli with the command
`docker exec -it fid /opt/radiantone/vds/bin/vdsconfig.sh`. Running it with no arguments opens a help menu that
describes the available options.

## Admin REST APIs

IDDM Lite supports an Admin REST API that can perform most IDDM configurations. Under normal circumstances it is an
internal-only API, so it is not covered by our official public documentation. If it turns out to be the best solution
for a specific configuration need, Radiant Logic support can guide you on how to use it.

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

## Exporting and Importing LDIF

To export data to an LDIF file, run:

```bash
docker exec -it fid /opt/radiantone/vds/bin/vdsconfig.sh export-ldif -basedn <basedn> -ldif <ldif> -scope sub -interactive
```

To import an LDIF file, run:

```bash
docker exec -it fid /opt/radiantone/vds/bin/vdsconfig.sh import-ldif -ldif <ldif> -interactive
```

Existing entries are not overwritten by an import.

Use a file path under `/opt/radiantone/vds/` for `<ldif>`, such as `/opt/radiantone/vds/ldif/export.ldif`. That
directory is mounted from `${IDDM_DATA_ROOT}/fid/vds/` on the server, so the same file is found there.

Deleting the application data deletes this file too. Before you delete it, copy the file to a location outside
`${IDDM_DATA_ROOT}`, and copy it back under `${IDDM_DATA_ROOT}/fid/vds/` before you import it.

The `-interactive` option makes the command wait and show progress until the task finishes. Without it, the task runs
in the background and the command returns at once.

More options exist for both commands. The Radiant Logic documentation and Radiant Logic support can help with them.
