# IDDM Lite

IDDM Lite is a custom IDDM deployment for limited, lightweight use cases. It sacrifices pieces of IDDM functionality to
substantially reduce resource requirements, so it can run on more limited hardware. This repository holds everything
you need to deploy and configure it, and this page points you to the guides that cover each task.

**Disclaimer:** This repository is provided solely for use by customers and users authorized by Radiant Logic. Standard
Radiant Logic license terms do not apply. Any unapproved customer or other party must contact Radiant Logic and receive
prior approval before accessing, using, or deploying its contents.

## Overview

### Cloning This Repo

The simplest way to deploy IDDM Lite on the in-store servers is to clone this repo onto the servers themselves. You then
use the resources in this repo to run and configure the IDDM Lite deployment.

### Customized Docker Images

This project provides slightly customized versions of two IDDM docker images: `fid` and `zookeeper`. Most of the
changes are to the `fid` image, and they ensure it can run in a lightweight mode on a resource-constrained server.

**Warning:** Under no circumstances should you modify the contents of the `./docker` directory. These images have been
crafted to achieve maximum functionality under restrictive conditions, and the configuration depends heavily on
knowledge of IDDM internals. Changing this directory independently of Radiant Logic could cause runtime errors, and it
will leave Radiant Logic support unable to adequately assist you in solving the issues.

### Setup Image

A special setup image is also provided. It is not the only way to configure the in-store IDDM Lite deployment. However,
IDDM Lite cannot use the robust configuration mechanisms of the full IDDM deployment, so this image automates several
critical and common flows. It should let you set up the in-store IDDM Lite deployments more rapidly.

### Docker Compose & Run Script

A `docker-compose.yml` file is provided with everything pre-configured. When you deploy this project on the server, the
compose file builds the images from the provided dockerfiles.

The `run.sh` script manages the lifecycle of the IDDM Lite deployment, using `docker-compose.yml`: starting, stopping
and setting it up. Alongside it, the `update_iddm_env.sh` script works out the correct Zookeeper base version for a
newer IDDM version and writes both into the `.env` file.

## Detailed Documentation

- [Using a Full IDDM as a Staging Environment](./documentation/FULL_IDDM_STAGING.md) (Recommended)
- [Installing IDDM Lite](./documentation/INSTALLING_IDDM_LITE.md)
- [Configuring IDDM Lite Using the Setup Image](./documentation/CONFIGURING_IDDM_LITE_SETUP_IMAGE.md)
- [Additional Configuration Mechanisms for IDDM Lite](./documentation/ADDITIONAL_CONFIGURATION_MECHANISMS.md)
- [Upgrading IDDM Lite to Newer IDDM Version](./documentation/UPGRADING_IDDM_LITE.md)
- [Adjusting IDDM Lite Memory](./documentation/IDDM_MEMORY.md)
