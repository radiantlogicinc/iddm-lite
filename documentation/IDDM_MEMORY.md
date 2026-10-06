# Adjusting IDDM Lite Memory

This guide covers how to adjust the memory settings for IDDM Lite.

## Memory Cap

The customer implementation IDDM Lite was designed for has an environment with a maximum of 4GB of RAM available. IDDM
Lite is allowed to consume 100% of that 4GB of memory, but that is the hard limit.

## Memory Settings

All memory settings are environment variables in the `.env` file, and every variable is an amount of memory in
Megabytes. The next few sections explain which component each variable controls.

The memory settings pre-configured in this repository are best-guess values, because this use case has not been
tested. Adjustments may become necessary in the future.

## FID - Primary Application Memory

The FID container is the primary application of IDDM Lite. `FID_CONTAINER_MAX_MEMORY_MB` controls the memory limit for
the whole container. FID is composed of three separate processes inside the container, and each one needs its own
memory cap:

- The server, controlled by `FID_SERVER_MAX_MEMORY_MB`. Allocate the vast majority of the available memory to this
  process.
- The scheduler, controlled by `FID_SCHEDULER_MAX_MEMORY_MB`.
- The sync agent, controlled by `FID_SYNC_AGENT_MAX_MEMORY_MB`.

The three process memory limits should add up to slightly less than the container limit, leaving some head room for the
container OS itself.

## Secondary Applications

Zookeeper is a critical datasource for IDDM Lite and runs alongside FID at all times. `ZOOKEEPER_MAX_MEMORY_MB`
controls its memory limit.

Lastly, the setup image needs its own memory allocation, although not very much. `SETUP_MAX_MEMORY_MB` controls it.
