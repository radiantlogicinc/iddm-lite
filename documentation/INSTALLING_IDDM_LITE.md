# Installing IDDM Lite

Installing IDDM Lite is a fairly simple process.

## Cloning Repository

First clone this repository to the in-store server. That will prepare everything that you need right away.

## Setup Environment Variables

Add a file called `.env-server` to the root of this project. It needs to be configured with some variables specific to this server. Fill it out with the following content:

```
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

NOTE: The `FID_ADMIN_API_KEY` can be just a randomly generated 32-character string.

## Starting the Application

Using the provided shell script, run the command `./run.sh start`. This will build and start the docker images for both Zookeeper & FID. Please be aware that FID takes some time to fully start due to the complexity of the server. 

## Application Data

The location specified in the `IDDM_DATA_ROOT` environment variable is where all data will be written out. This is the structure it can be expected to have once startup is complete:

```
${IDDM_DATA_ROOT}/
  zookeeper/
  fid/
  git/
```

## Stopping the Application

To stop the application, run the command `./run.sh stop`.

## Re-Building the Application Images

The application images are build the first time they are started and stored in the local container runtime. To re-build the application images if there are any changes to the docker builds, run `./run.sh build-iddm`.