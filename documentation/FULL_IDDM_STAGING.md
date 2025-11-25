# Using a Full IDDM as a Staging Environment

IDDM Lite can be configured directly if necessary, however that process is not nearly as streamlined as the full IDDM. Because of this, it is recommended to use a full IDDM as a staging environment. This document will explain why

## How it Works

### Developing Configurations on Staging IDDM

The "staging" IDDM would be a full deployment to kubernetes that exists exclusively to develop and test new configurations. It should be treated as if it was an in-store IDDM, even though it will likely be in a more central corporate location. The full suite of IDDM configuration tools will be available in this environment. The combination of a robust UI coupled with a well-documented public API will make the experience easy. 

### Promoting Configurations to In-Store IDDM

On top of this easy configuration experience, transferring the configurations from the staging environment to the in-store IDDM Lite will also be very simple. IDDM comes with a feature called Config Promotion, it's a new addition first released in 8.1.5. This is a fully automated system designed to move configurations from one IDDM to another. It also fully supports a "one to many" promotion model, where the staging IDDM can have its configurations promoted to the full suite of store IDDMs. Essentially it would look something like this:

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

https://developer.radiantlogic.com/idm/v8.1/installation/config-promotion/