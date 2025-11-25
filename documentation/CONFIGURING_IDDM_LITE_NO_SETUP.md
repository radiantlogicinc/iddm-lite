# Configuring IDDM Lite Without Using the Setup Image

If the Config Promotion based workflow isn't appropriate for Home Depot's needs, or if there are some additional requirements that just aren't properly supported by what is provided in the setup image, there are other configuration options. This is a quick overview of what they are.

## No UI and No Configuration APIs

The strict Home Depot resource requirements, specifically the 4GB RAM cap, means that many components of IDDM had to be dropped to meet these restrictions.

## VDSConfig

The VDSConfig utility is a CLI based tool for configuring IDDM. It is an older part of the product that, while still fully functional, may not support all the latest bells and whistles since all functionality is being migrated to the new Configuration APIs.