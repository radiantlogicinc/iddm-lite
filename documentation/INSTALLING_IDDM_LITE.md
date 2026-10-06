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

## Stopping the Application

To stop the application, run `./run.sh stop`.

## Re-Building the Application Images

The application images are built the first time they are started, and they are stored in the local container runtime. If
there are any changes to the docker builds, run `./run.sh build-iddm` to re-build the application images.
