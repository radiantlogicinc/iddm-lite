# Using a Full IDDM as a Staging Environment

IDDM Lite can be configured directly if necessary, however that process is not nearly as streamlined as the full IDDM. Because of this, it is recommended to use a full IDDM as a staging environment. This document will explain why

## How it Works

### Developing Configurations on Staging IDDM

The "staging" IDDM would be a full deployment to kubernetes that exists exclusively to develop and test new configurations. It should be treated as if it was an in-store IDDM, even though it will likely be in a more central corporate location. The full suite of IDDM configuration tools will be available in this environment. The combination of a robust UI coupled with a well-documented public API will make the experience easy. 

### Renaming Is an Option - But Not Recommended

The naming context that represents the store's data, if necessary, can be renamed upon import. This means that in the staging IDDM it can be called one thing (ie, `ou=staging-store`) and then on the in-store IDDM Lite it can be called something else (ie, `ou=store1`). This is a mechanism that is handled by the setup image during IDDM Lite configuration.

Any context that will be renamed upon import should have as unique a name as possible at the RDN level, because that is the level the rename operation takes place upon.

WARNING: While this option exists and should work, it is strongly recommended to avoid this approach. Context renaming is a complex operation designed specifically for a single customer request, and it may not be able to handle all configuration permutations.

### Promoting Configurations to In-Store IDDM

On top of this easy configuration experience, transferring the configurations from the staging environment to the in-store IDDM Lite will also be very simple. IDDM comes with a feature called Config Promotion, it's a new addition first released in 8.1.5. This is a fully automated system designed to move configurations from one IDDM to another. It also fully supports a "one to many" promotion model, where the staging IDDM can have its configurations promoted to the full suite of store IDDMs. It uses git as a medium of exchange, pushing the configurations to a git repository when exported from staging and pulling them back down when importing to the store IDDM Lites.

This means that as soon as the Staging IDDM is good to go, the configurations can quickly and easily be transferred to the in-store IDDMs. It would look something like this:

```
                  --> Store 1 IDDM Lite
                 |
                  --> Store 2 IDDM Lite  
                 |   
Staging IDDM ----    
                 |   
                  --> Store 3 IDDM Lite 
                 |
                  --> Store 4 IDDM Lite
```

Promoting the configurations requires running the Promotion Export on the Staging IDDM, and then using the setup image provided with this project do to the import on the in-store IDDM Lite.

## More Config Promotion Information

The following is the official documentation for Config Promotion.

User Guide: https://developer.radiantlogic.com/idm/v8.1/deployment/configuration-promotion/

Self Managed Kubernetes Guide: https://developer.radiantlogic.com/idm/v8.1/installation/config-promotion/