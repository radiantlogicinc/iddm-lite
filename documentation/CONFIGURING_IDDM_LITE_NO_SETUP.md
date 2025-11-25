# Configuring IDDM Lite Without Using the Setup Image

If the Config Promotion based workflow isn't appropriate for Home Depot's needs, or if there are some additional requirements that just aren't properly supported by what is provided in the setup image, there are other configuration options. This is a quick overview of what they are.

## No UI and No Configuration APIs

The strict Home Depot resource requirements, specifically the 4GB RAM cap, means that many components of IDDM had to be dropped to meet these restrictions. This means that critical dependencies necessary for both the IDDM UI and the Configuration APIs are not available on the IDDM Lite in-store deployments. If in the future 8GB of RAM becomes available on each in-store server, then this restriction can be lifted and a full IDDM can be deployed in each store.

## VDSConfig

The VDSConfig utility is a CLI based tool for configuring IDDM. It is an older part of the product that, while still fully functional, may not support all the latest bells and whistles since all functionality is being migrated to the new Configuration APIs.

VDSConfig will exist on the filesystem of the in-store server at `${IDDM_DATA_ROOT}/fid/vds/bin/vdsconfig.sh`, however it is recommended to only exercise it from inside the running FID docker container since it needs in-depth connectivity with the FID application itself. This can be done by running `docker exec -it fid /opt/radiantone/vds/bin/vdsconfig.sh` on the in-store server. Running the command with no arguments will open a help menu that will describe the various options available.

## Admin REST APIs

IDDM Lite supports an Admin REST API that can be used to perform most IDDM configurations. However, this is an internal-only API under normal circumstances, which means it is not covered by our official public documentation. That being said, Radiant Logic support can provide guidance on how to leverage this API if it ends up being the best solution for specific configuration needs.