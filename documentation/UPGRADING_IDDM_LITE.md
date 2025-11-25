# Upgrading IDDM Lite to Newer IDDM Version

Upgrading IDDM Lite to a newer version of IDDM is fully supported and should be nealy effortless. This is how to do it.

## Update the Version

In the `.env` file at the root of this project, there is a property `IDDM_VERSION`. Simply update it to the desired IDDM release version.

## Stop, Rebuild, and Start

To perform the upgrade, first stop the running IDDM Lite application with `./run.sh stop`. Then rebuild the images with `./run.sh build-iddm`. Lastly, start IDDM Lite again with `./run.sh start`.

This will automatically perform an upgrade operation on the IDDM Lite application during its startup, so it may take a little bit longer than normal. Once it completes, IDDM Lite will be running on the newer version.