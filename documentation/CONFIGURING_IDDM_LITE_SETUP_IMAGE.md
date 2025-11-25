# Configuring IDDM Lite Using the Setup Image

The setup image bundled with this project is optimized for configuring IDDM Lite with Config Promotion. This means the configurations should be developed and tested using the full staging IDDM and then exported so they are ready to be used in-store.

This guide will explain how to use the setup image to perform the import and automate a few extra configuration steps that may be needed beyond the import.

## The Setup Directory

For all operations using the setup image, files must be placed into a directory called `setup` within the root data directory of the project. It would look like this:

```
${IDDM_DATA_ROOT}/
  setup/
```

The files placed here are control files that the setup image will use to determine which operations to perform. The individual files will be described in subsequent sections.

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

## Adding 