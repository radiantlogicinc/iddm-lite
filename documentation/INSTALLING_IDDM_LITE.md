# Installing IDDM Lite

Follow these steps to install IDDM Lite on an in-store server: clone the repository, create the server-specific
environment file, and start the application.

## Cloning Repository

First clone this repository to the in-store server. That prepares everything you need right away.

## Setup Environment Variables

Add a file called `.env-server` to the root of this project. It holds the variables specific to this server. Fill it out
with the following content:

```sh
# Data locations
IDDM_DATA_ROOT=

# Cluster Info
CLUSTER_NAME=

# Credentials
IDDM_ROOT_PASSWORD=
ZOOKEEPER_PASSWORD=
IDDM_LICENSE=
FID_ADMIN_API_KEY=
```

**Note:** `FID_ADMIN_API_KEY` can be just a randomly generated 32-character string.

## File Permissions

The containers write all application data under `IDDM_DATA_ROOT` as the user that the docker daemon runs as. If docker
runs as `root`, every file and directory it creates there is owned by `root`. Reading, copying, or deleting those files
directly on the server then requires `sudo`.

Keep this in mind whenever you work with the files under `IDDM_DATA_ROOT`, such as LDIF exports or the application data
itself.

## Starting the Application

Run `./run.sh start`. This builds and starts the docker images for both Zookeeper & FID. FID takes some time to fully
start, due to the complexity of the server.

## Application Data

The location in the `IDDM_DATA_ROOT` environment variable is where all application data is written. Once startup is
complete, it has this structure:

```text
${IDDM_DATA_ROOT}/
  zookeeper/
  fid/
```

The `setup/` directory, if present, is not application data. It holds the control files you supply for the setup image,
as described in [Configuring IDDM Lite Using the Setup Image](./CONFIGURING_IDDM_LITE_SETUP_IMAGE.md).

## Stopping the Application

To stop the application, run `./run.sh stop`.

## Re-Building the Application Images

The application images are built the first time they are started, and they are stored in the local container runtime. If
there are any changes to the docker builds, run `./run.sh build-iddm` to re-build the application images.

## Deleting Application Data

Deleting the application data returns IDDM Lite to a fresh install. Two things must be true for the application to work
again afterwards:

- **The existing containers must be deleted too.** The `zookeeper` and `fid` containers on the server, and `fid-setup`
  if it exists, hold state that matches the old data. Starting them against an empty `IDDM_DATA_ROOT` leaves IDDM Lite
  in a broken state.
- **The files must be deleted with the right permissions.** If docker runs as `root`, the data is owned by `root` and
  must be deleted with `sudo`. See [File Permissions](#file-permissions). A partial delete leaves IDDM Lite in a broken
  state.

Only delete `${IDDM_DATA_ROOT}/zookeeper/` and `${IDDM_DATA_ROOT}/fid/`. Keep `${IDDM_DATA_ROOT}/setup/`, since the
setup image needs its control files to configure IDDM Lite again.

Back up anything you need first, such as data exported to LDIF. See
[Exporting and Importing LDIF](./ADDITIONAL_CONFIGURATION_MECHANISMS.md#exporting-and-importing-ldif).

### Using the Clean Command

The `clean` command performs the whole deletion safely:

1. Stop IDDM Lite with `./run.sh stop`.
2. Run `./run.sh clean`. It lists what it removes and asks for confirmation. Pass `--yes` to skip the prompt.
3. Start IDDM Lite with `./run.sh start`. The application images are rebuilt, since `clean` removes them.

`clean` deletes `zookeeper/` and `fid/`, keeps `setup/`, and removes the `zookeeper`, `fid` and `fid-setup` containers
along with the built images. If docker runs as `root`, run it with `sudo` so that it can delete the data.

### Deleting Manually

1. Stop IDDM Lite with `./run.sh stop`.
2. Remove the containers with `docker rm zookeeper fid fid-setup`.
3. Delete the data with `sudo rm -rf "${IDDM_DATA_ROOT}/zookeeper" "${IDDM_DATA_ROOT}/fid"`. Leave out `sudo` if docker
   does not run as `root`.
4. Start IDDM Lite with `./run.sh start`.
