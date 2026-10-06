# Using a Full IDDM as a Staging Environment

You can configure IDDM Lite directly if necessary, but that process is not nearly as streamlined as with the full IDDM.
We therefore recommend using a full IDDM as a staging environment. This guide explains why.

## How it Works

### Developing Configurations on Staging IDDM

The "staging" IDDM is a full deployment to kubernetes that exists exclusively to develop and test new configurations.
Treat it as if it were an in-store IDDM, even though it will likely be in a more central corporate location. The full
suite of IDDM configuration tools is available in this environment, and a robust UI coupled with a well-documented
public API makes the experience easy.

### Renaming Is an Option - But Not Recommended

If necessary, you can rename the naming context that represents the store's data when you import it. In the staging
IDDM it can be called one thing (for example, `ou=staging-store`), and on the in-store IDDM Lite it can be called
something else (for example, `ou=store1`). The setup image handles this during IDDM Lite configuration.

Give any context that will be renamed on import as unique a name as possible at the RDN level, because that is the
level at which the rename takes place.

**Warning:** While this option exists and should work, we strongly recommend avoiding it. Context renaming is a complex
operation designed specifically for a single customer request, and it may not be able to handle all configuration
permutations.

### Promoting Configurations to In-Store IDDM

Transferring the configurations from the staging environment to the in-store IDDM Lite is also very simple. IDDM comes
with a feature called Config Promotion, a new addition first released in 8.1.5. It is a fully automated system that
moves configurations from one IDDM to another. It also fully supports a "one to many" promotion model, where the
staging IDDM promotes its configurations to the full suite of store IDDMs. It uses git as a medium of exchange: you push
the configurations to a git repository when you export from staging, and the store IDDM Lites pull them back down when
you import.

As soon as the staging IDDM is good to go, the configurations can be transferred to the in-store IDDMs quickly and
easily. It looks something like this:

```text
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

To promote the configurations, run the Promotion Export on the staging IDDM, and then use the setup image provided with
this project to do the import on the in-store IDDM Lite.

## More Config Promotion Information

The following is the official documentation for Config Promotion.

User Guide: https://developer.radiantlogic.com/idm/v8.1/deployment/configuration-promotion/

Self Managed Kubernetes Guide: https://developer.radiantlogic.com/idm/v8.1/installation/config-promotion/
