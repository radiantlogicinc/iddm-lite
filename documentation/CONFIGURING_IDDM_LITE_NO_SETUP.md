# Configuring IDDM Lite Without Using the Setup Image

If the Config Promotion based workflow isn't appropriate for a customer's needs, or if there are some additional requirements that just aren't properly supported by what is provided in the setup image, there are other configuration options. This is a quick overview of what they are.

## No UI and No Configuration APIs

IDDM Lite has been designed to operate under extraordinarily stringent resource constraints, most notably a cap of 4GB of RAM. Due to this, the UI and Configuration APIs will not be available for this deployment. 8GB of RAM is the minimum required for running IDDM with all of its features available.

## VDSConfig

The VDSConfig utility is a CLI based tool for configuring IDDM. It is an older part of the product that, while still fully functional, may not support all the latest bells and whistles since all functionality is being migrated to the new Configuration APIs.

Running vdsconfig can be done via the docker cli with the command `docker exec -it fid /opt/radiantone/vds/bin/vdsconfig.sh` on the in-store server. Running the command with no arguments will open a help menu that will describe the various options available.

## Admin REST APIs

IDDM Lite supports an Admin REST API that can be used to perform most IDDM configurations. However, this is an internal-only API under normal circumstances, which means it is not covered by our official public documentation. That being said, Radiant Logic support can provide guidance on how to leverage this API if it ends up being the best solution for specific configuration needs.