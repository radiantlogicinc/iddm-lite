# Configuring IDDM Lite Using the Setup Image

The setup image bundled with this project is optimized for configuring IDDM Lite with Config Promotion. This means the configurations should be developed and tested using the full staging IDDM and then exported so they are ready to be used in-store.

This guide will explain how to use the setup image to perform the import and automate a few extra configuration steps that may be needed beyond the import.

## Running the Setup Image

This is a fairly simple process command that is executed in this project: `./run.sh setup`. This will execute all setup tasks. Please see the sections below as they will cover how to supply the configuration necessary for setup to be performed successfully.

The setup image is built on the local machine and published to the local container registry. If it needs to be rebuilt, simply run `./run.sh build-setup`.

## The Setup Directory

For all operations using the setup image, files must be placed into a directory called `setup` within the root data directory of the project. It would look like this:

```
${IDDM_DATA_ROOT}/
  setup/
```

The files placed here are control files that the setup image will use to determine which operations to perform. The individual files will be described in subsequent sections.

NOTE: `IDDM_DATA_ROOT` is defined in the `.env-server` file that is created during the installation process. Please see [Installing IDDM Lite](./INSTALLING_IDDM_LITE.md) for more details.

## Performing the Import

### Using Git

The simplest way to do the import is using git. By providing the necessary git configurations, you can pull down the changes from the promotion git repository easily. To configure the setup process to do this, place a control file called `iddm-promotion-git.sh` into the setup directory (`${IDDM_DATA_ROOT}/setup/iddm-promotion-git.sh`) with the following contents:

```sh
export GIT_REPO=
export GIT_SSH_KEY_BASE64=
export GIT_BRANCH=
```

NOTE: The `GIT_REPO` is the ssh-based URL used for cloning.

### Using Zip

If for some reason git cannot be accessed on the in-store servers, the content can be downloaded from the promotion git repository as a zip file and placed on the machine. It must be placed in the setup directory with the name `iddm-promotion.zip` (`${IDDM_DATA_ROOT}/setup/iddm-promotion.zip`).

The primary issue with the zip approach is needing to transfer the data manually to each store. Otherwise, it is just as effective as the git approach.

## Renaming Contexts

It is possible to rename context RDNs during the import. If you want to do this, you can place a control file called `iddm-promotion-rename-{NUMBER}.sh` into the setup directory, where the `NUMBER` is an incrementing integer based on how many of these operations you want to take place (`${IDDM_DATA_ROOT}/setup/iddm-promotion-rename-1.sh`). The file needs to have the following contents:

```sh
export SOURCE_RDN=
export TARGET_RDN=
```

WARNING: This is not recommended. The feature was designed exclusively for a specific customer request, and it may not support all permutations of configurations. If the rename fails in any way, runtime errors are guaranteed. Use this carefully and only with thorough testing. 

## Configuring Datasources

Because of the expectation that promoting configurations between environments may result in datasources targeting a different system (ie, moving from QA to Prod databases), datasources are promoted only as a shell. This means that after a promotion import, the datasource connection information must be supplied manually. The setup image is configured to make this process fairly streamlined, supporting both database (ie, SQL) and LDAP datasources.

First, you need to place a control file called `iddm-promotion-datasource-{NUMBER}.sh` into the setup directory, where the `NUMBER` is an incrementing integer based on how many of these operations you want to take place (`${IDDM_DATA_ROOT}/setup/iddm-promotion-datasource-1.sh`). The file contents will be based on the type of datasource being configured.

For a database datasource:

```sh
# Do not change CATEGORY, it determines that we are using a database
export CATEGORY=database
# The NAME must match the name of the datasource that was imported
export NAME=
export JDBC_URL=
export USERNAME=
export PASSWORD=
```

For an LDAP datasource:

```sh
# Do not change CATEGORY, it determines that we are using an ldap
export CATEGORY=ldap
# The NAME must match the name of the datasource that was imported
export NAME=
export HOST=
export PORT=
export IS_SSL=
export BIND_DN=
export BIND_PASSWORD=
```

## Configuring Certificates

Config Promotion does not currently cover all IDDM configurations, although it will be expanded to cover all missing areas over the next several releases. One area that is not covered by Config Promotion currently is client certificates. If any datasources require a certificate to be loaded into the IDDM Lite deployment in order to connect to the target system, this has to be done via an extra step after the import.

To do this, simply place the certificate file into the setup directory in PEM format (`${IDDM_DATA_ROOT}/setup/certificate.pem`). Keep in mind the file name will become the certificate alias when loaded into IDDM Lite.

Any PEM files that are found during the setup flow will be loaded into the IDDM Lite deployment.