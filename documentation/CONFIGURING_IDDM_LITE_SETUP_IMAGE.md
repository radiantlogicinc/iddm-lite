# Configuring IDDM Lite Using the Setup Image

The setup image bundled with this project configures IDDM Lite with Config Promotion. You develop and test the
configurations on the full staging IDDM, export them, and then import them in-store. This guide shows how to run the
setup image to perform the import, and how to automate the extra configuration steps that may be needed beyond it.
Additional operations you may need alongside setup are covered in
[Additional Configuration Mechanisms for IDDM Lite](./ADDITIONAL_CONFIGURATION_MECHANISMS.md).

## Config Promotion Disclaimer: Add and Update Work, Delete Does Not

**Disclaimer:** Config Promotion in IDDM Lite cannot delete resources. IDDM Lite has a 4GB limit on the available RAM
on the in-store servers, so many components of IDDM could not be included. The components needed to work out which
changes to apply during a promotion import are among those left out.

As a result, a promotion import simply adds or updates every resource included in the promotion. That is harmless as
long as the promotion resources only add, update, or leave existing resources unchanged. However, the import cannot
automatically remove deleted resources.

For this reason, if you use the setup image, we recommend this sequence:

1. Shut down IDDM Lite with `./run.sh stop`.
2. Delete the application data and the existing containers, as described in
   [Deleting Application Data](./INSTALLING_IDDM_LITE.md#deleting-application-data).
3. Restart IDDM Lite with `./run.sh start`.
4. Run the setup again with `./run.sh setup`.

Back up any data involved by exporting it to LDIF and importing it again later, as described in
[Exporting and Importing LDIF](./ADDITIONAL_CONFIGURATION_MECHANISMS.md#exporting-and-importing-ldif). Keep the
`setup/` directory when you delete the data, since step 4 needs its control files.

## Running the Setup Image

Run `./run.sh setup` in this project. It executes all setup tasks. The sections below cover how to supply the
configuration that setup needs in order to succeed.

Before any operation, setup runs a series of checks against FID to make sure it is ready, and waits an appropriate
amount of time for each one to pass. If FID does not become ready, setup stops. See
[Setup says FID was not ready](#setup-says-fid-was-not-ready).

To see more detail about what the setup image is doing, run `./run.sh setup --debug`. This prints the setup tool's own
`[DEBUG]` lines. It also raises the VDS Server log level to `DEBUG` once FID is ready, so FID's `vds_server.log` is
detailed too. Setup restores the previous level when it ends.

The setup image is built on the local machine and stored in the local container runtime. To rebuild it, run
`./run.sh build-setup`.

### Setup says FID was not ready

If FID does not become ready, setup stops with a `FID was not ready: ...` message that names the check that failed.

To find the cause:

1. Run `docker logs fid` and look for startup errors.
2. Check the credentials setup uses: `IDDM_ROOT_USERNAME` in `.env`, and `IDDM_ROOT_PASSWORD` and `FID_ADMIN_API_KEY`
   in `.env-server`.
3. Run `./run.sh setup` again once FID is healthy.

## The Setup Directory

For all operations that use the setup image, you place files in a directory called `setup` within the root data
directory of the project:

```text
${IDDM_DATA_ROOT}/
  setup/
```

The files you place here are control files. The setup image reads them to decide which operations to perform. The
sections below describe each file.

**Note:** `IDDM_DATA_ROOT` is defined in the `.env-server` file that you create during installation. See
[Installing IDDM Lite](./INSTALLING_IDDM_LITE.md) for more details.

## Performing the Import

### Using Git

Git is the simplest way to do the import. With the necessary git configuration, setup pulls the changes down from the
promotion git repository. To set this up, place a control file called `iddm-promotion-git.sh` in the setup directory
(`${IDDM_DATA_ROOT}/setup/iddm-promotion-git.sh`) with the following contents:

```sh
export GIT_REPO=
export GIT_SSH_KEY_BASE64=
export GIT_BRANCH=
```

**Note:** `GIT_REPO` is the ssh-based URL used for cloning.

### Using Zip

If the in-store servers cannot access git, download the content from the promotion git repository as a zip file and
place it on the machine. Put it in the setup directory with the name `iddm-promotion.zip`
(`${IDDM_DATA_ROOT}/setup/iddm-promotion.zip`).

The only real drawback of the zip approach is that you must transfer the data to each store manually. Otherwise, it is
just as effective as the git approach.

## Configuring Datasources

Promoting configurations between environments can change which system a datasource targets, for example when moving
from QA to Prod databases. Datasources are therefore promoted only as a shell, and after a promotion import you must
supply the datasource connection information yourself. The setup image streamlines this and supports both database
(for example, SQL) and LDAP datasources.

Place a control file called `iddm-promotion-datasource-{NUMBER}.sh` in the setup directory, such as
`${IDDM_DATA_ROOT}/setup/iddm-promotion-datasource-1.sh`. `NUMBER` is an incrementing integer, with one file for each
datasource update you want. The file contents depend on the type of datasource being configured.

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
# Do not change CATEGORY, it determines that we are using an LDAP datasource
export CATEGORY=ldap
# The NAME must match the name of the datasource that was imported
export NAME=
export HOST=
export PORT=
export IS_SSL=
export BIND_DN=
export BIND_PASSWORD=
```

## Redirecting an LDAP Proxy's Remote Base DN

A promoted LDAP proxy naming context keeps the proxy remote base DN it had in the source environment. When a store's
remote LDAP server holds the data under a different DN, place a control file called `proxy-remote-base-dn-{NUMBER}.sh`
in the setup directory (`${IDDM_DATA_ROOT}/setup/proxy-remote-base-dn-1.sh`) with these contents:

```sh
# The DN of the context to proxy to in the remote LDAP server
export REMOTE_BASE_DN=
# The DN of the LDAP proxy naming context as it exists in IDDM Lite
export LDAP_PROXY_DN=
```

Both values are required. The naming context must already exist in IDDM Lite, so it has to come in with the promotion.

To redirect more than one proxy, add more files, numbered `-2`, `-3`, and so on. Setup applies these files after the
certificate import, the promotion import and the datasource updates.

Setup uses `IDDM_ROOT_USERNAME` and `IDDM_ROOT_PASSWORD` to reach ADAP, both here and for the readiness check at the
start of every run. If a file is missing a value, or FID rejects the change, setup stops with an error.

## Configuring Certificates

Config Promotion does not currently cover all IDDM configurations, although it will be expanded to cover the missing
areas over the next several releases. Client certificates are one area it does not cover. If any datasource needs a
certificate loaded into the IDDM Lite deployment in order to connect to the target system, you do this in an extra step
after the import.

Place the certificate file in the setup directory in PEM format (`${IDDM_DATA_ROOT}/setup/certificate.pem`). The file
name becomes the certificate alias when the certificate is loaded into IDDM Lite.

Setup loads any PEM files it finds into the IDDM Lite deployment.

## Renaming Contexts - USE AT YOUR OWN RISK

You can rename context RDNs during the import. To do so, place a control file called
`iddm-promotion-rename-{NUMBER}.sh` in the setup directory, such as
`${IDDM_DATA_ROOT}/setup/iddm-promotion-rename-1.sh`. `NUMBER` is an incrementing integer, with one file for each
rename you want. The file needs these contents:

```sh
export SOURCE_RDN=
export TARGET_RDN=
```

**Warning:** This is not recommended. The feature was designed exclusively for a specific customer request, and it may
not support all permutations of configurations. If the rename fails in any way, runtime errors are guaranteed. Use it
carefully and only with thorough testing.
