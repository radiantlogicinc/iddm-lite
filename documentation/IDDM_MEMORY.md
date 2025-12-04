# Adjusting IDDM Lite Memory

This guide covers how to adjust the memory settings for IDDM Lite.

## Memory Cap

The customer implementation this has been designed for has an environment with a maximum of 4GB of RAM available. IDDM Lite is allowed to consume 100% of that 4GB of memory, but that is the hard limit.

## Memory Settings

All memory settings are controlled via environment variables configured in the `.env` file. All the variables represent an amount of memory in Megabytes. The next few sections explain which components each variable controls.

The memory settings pre-configured in this repository represent best-guess values. Without actual testing of this use case, that is the best that can be done. Adjustments in the future may become necessary.

## FID - Primary Application Memory

The FID container is the primary application of IDDM Lite. The memory limit for the whole container is controlled by the `FID_CONTAINER_MAX_MEMORY_MB`. However, FID is composed of three separate processes inside of the container, each one needs its own memory cap. These are:

- The server, controlled by `FID_SERVER_MAX_MEMORY_MB`. The vast majority of the available memory should be allocated to this process.
- The scheduler, controlled by `FID_SCHEDULER_MAX_MEMORY_MB`.
- The sync agent, controlled by `FID_SYNC_AGENT_MAX_MEMORY_MB`.

The three process memory limits should add up to slightly less than the container limit, leaving some head room for the container OS itself.

## Secondary Applications

Zookeeper is a critical datasource for IDDM Lite and will be running alongside FID at all times. The memory limit for Zookeeper is controlled by the `ZOOKEEPER_MAX_MEMORY_MB` variable.

Lastly, the setup image needs its own memory allocation, although it does not need very much. This is controlled by the `SETUP_MAX_MEMORY_MB` variable.