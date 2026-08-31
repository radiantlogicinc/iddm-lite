# Upgrading IDDM Lite to Newer IDDM Version

Upgrading IDDM Lite to a newer version of IDDM is fully supported and should be nearly effortless. This is how to do it.

## The Version Variables

The `.env` file at the root of this project controls which images IDDM Lite runs:

- `IDDM_VERSION` is the IDDM release that IDDM Lite tracks, such as `8.5.2`. This is the version you change when upgrading.
- `ZOOKEEPER_BASE_VERSION` is the version of Zookeeper itself, such as `3.5.8`. It is separate from the IDDM release and changes very infrequently, so it will usually stay the same across an upgrade.
- `ZOOKEEPER_VERSION` is derived automatically from the two variables above, because the Zookeeper images are tagged with both. Never edit it by hand.

Rather than working out the right values yourself, use the `update_iddm_env.sh` script described below. It looks up the correct `ZOOKEEPER_BASE_VERSION` for the IDDM version you want and writes both variables to `.env` together, so they can never fall out of step.

NOTE: The script requires the `jq` and `curl` commands to be installed on the server.

## Update the Version

From the root of this project, run:

```
./update_iddm_env.sh
```

It will ask which IDDM version to upgrade to, offering the current version as the default. Enter the desired IDDM release version and press enter.

The script then checks which Zookeeper image has been published for that IDDM release and updates `.env` accordingly. If it reports a problem instead, nothing will have been changed. Read the message and follow what it tells you to do.

## Stop, Rebuild, and Start

To perform the upgrade, first stop the running IDDM Lite application with `./run.sh stop`. Then rebuild the images with `./run.sh build-iddm`. Lastly, start IDDM Lite again with `./run.sh start`.

This will automatically perform an upgrade operation on the IDDM Lite application during its startup, so it may take a little bit longer than normal. Once it completes, IDDM Lite will be running on the newer version.
