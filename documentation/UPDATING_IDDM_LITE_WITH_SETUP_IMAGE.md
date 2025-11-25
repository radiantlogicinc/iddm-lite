# Updating IDDM Lite With Setup Image

The following section covers how to update IDDM Lite with the provided setup image.

## Config Promotion - Add/Update Works, Delete Does Not

Due to the 4GB limit on the available RAM on the in-store servers, many components of IDDM could not be included in IDDM Lite. One of the consequnces of this is that deleting resources via Config Promotion will not work. The requires components to properly understand what changes to apply during a promotion import are not present in IDDM Lite.

This means that any promotion import will simply add or update all resources included in the promotion. This is harmless so long as the promotion resources either Add, Update, or don't change existing resources. However, it will not be capable of automatically removing deleted resources.

For this reason, if the setup image is used, it is recommended to shut down IDDM Lite using `./run.sh stop`, delete all data, and then restart IDDM Lite using `./run.sh start` and run the setup again with `./run.sh setup`. Any data involved can be easily backed up by exporting it to LDIF files and then re-uploading later on.