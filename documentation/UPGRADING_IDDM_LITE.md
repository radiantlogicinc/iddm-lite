# Upgrading IDDM Lite to Newer IDDM Version

Upgrading IDDM Lite to a newer IDDM version is fully supported and should be nearly effortless. You update the version
in `.env` with a script, then stop, rebuild and start the application.

## The Version Variables

The `.env` file at the root of this project controls which images IDDM Lite runs:

- `IDDM_VERSION` is the IDDM version that IDDM Lite tracks, such as `8.5.2`. This is the version you change when you
  upgrade.
- `ZOOKEEPER_BASE_VERSION` is the Zookeeper base version, the version of Zookeeper itself, such as `3.5.8`. It is
  separate from the IDDM version and changes very infrequently, so it usually stays the same across an upgrade.
- `ZOOKEEPER_VERSION` is derived automatically from the two variables above, because the Zookeeper images are tagged
  with both. Never edit it by hand.

Rather than working out the right values yourself, use the `update_iddm_env.sh` script described below. It looks up the
correct `ZOOKEEPER_BASE_VERSION` for the IDDM version you want and writes both variables to `.env` together, so they
can never fall out of step.

**Note:** The script requires the `jq` and `curl` commands to be installed on the server.

## Update the Version

From the root of this project, run:

```bash
./update_iddm_env.sh
```

The script asks which IDDM version to upgrade to, and offers the current version as the default. Enter the IDDM version
you want and press enter.

The script then checks which Zookeeper image has been published for that IDDM version and updates `.env` accordingly.
If it reports a problem instead, it has changed nothing. Read the message and follow what it tells you to do.

## Stop, Rebuild, and Start

To perform the upgrade, first stop the running IDDM Lite application with `./run.sh stop`. Then rebuild the images with
`./run.sh build-iddm`. Lastly, start IDDM Lite again with `./run.sh start`.

IDDM Lite automatically performs an upgrade operation on the application during startup, so startup may take a little
longer than normal. Once it completes, IDDM Lite is running on the newer version.
