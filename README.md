# IDDM Lite

This is the configuration for the "IDDM Lite" custom deployment. It is a stripped-down version of IDDM designed for limited, lightweight use cases. This document will explain how to leverage it to most effectively.

## Overview

### Cloning This Repo

The simplest approach to deploying IDDM Lite on the in-store servers is to clone this repo onto the servers themselves. Then use the provided resources in this repo to run and configure the IDDM Lite deployment.

### Customized Docker Images

This project provides slightly customized versions of two IDDM docker images: `fid` and `zookeeper`. Most of the changes are to the `fid` image, and are designed to ensure it can run in a lightweight mode on a resource-constrained server.

WARNING: Under no circumstances should the contents of the `./docker` directory be modified. These images have been crafted to achieve maximum functionality under restrictive conditions, and the configuration heavily depends on knowledge of IDDM internals. Making changes to the contents of this directory independent of Radiantlogic could result in runtime errors and will leave Radiantlogic support unable to adequately assist you in solving the issues.

### Setup Image

A special setup image has been prepared as well. This image is not the only way to configure the in-store IDDM Lite deployment. However, given that IDDM Lite cannot leverage the robust configuration mechanisms of the full IDDM deployment, this image is designed to easily automate several critical and common flows. It will hopefully enable the in-store IDDM Lite deployments to be setup more rapidly.

### Docker Compose & Run Script

A `docker-compose.yml` file is provided with everything pre-configured. The compose file is designed to build the images from the provided dockerfiles when this project is deployed on the server itself. There is also a `run.sh` script that will manage the lifecycle of starting, stopping, and setting up the IDDM Lite deployment using the `docker-compose.yml` file.

## Detailed Documentation

- [Using a Full IDDM as a Staging Environment](./documentation/FULL_IDDM_STAGING.md) (Recommended)
- [Installing IDDM Lite](./documentation/INSTALLING_IDDM_LITE.md)
- [Configuring IDDM Lite Using the Setup Image](./documentation/CONFIGURING_IDDM_LITE_SETUP_IMAGE.md)
- [Updating IDDM Lite With Setup Image](./documentation/UPDATING_IDDM_LITE_WITH_SETUP_IMAGE.md)
- [Configuring IDDM Lite Without Setup Image](./documentation/CONFIGURING_IDDM_LITE_NO_SETUP.md)
- [Upgrading IDDM Lite to Newer IDDM Version](./documentation/UPGRADING_IDDM_LITE.md)
- [Adjusting IDDM Lite Memory](./documentation/IDDM_MEMORY.md)