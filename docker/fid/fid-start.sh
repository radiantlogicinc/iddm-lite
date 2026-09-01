#!/usr/bin/env bash

# Not using bash strict mode because much of this is copied verbatim from existing code that does not use it

ZK_HOST=zookeeper
ZK_CLIENT_PORT=2181
ZK_ADMIN_PORT=8080
ZK_WAIT_INTERVAL=2
# 150 attempts ZK_WAIT_INTERVAL seconds apart gives zookeeper 5 minutes to become ready
ZK_WAIT_ATTEMPTS=150

# Probes the zookeeper client port, which is the port FID itself connects to. The -w timeout
# bounds the connect so a filtered or blackholed endpoint cannot stall the loop.
zk_port_is_open() {
  nc -w "$ZK_WAIT_INTERVAL" -z "$ZK_HOST" "$ZK_CLIENT_PORT" > /dev/null 2>&1
}

# Probes the zookeeper admin server's is_read_only command. The admin server answers HTTP 200
# even while zookeeper is still starting, returning an `error` field in place of the
# `read_only` field, so the response body has to be inspected rather than the status code.
# The `|| return 1` keeps a failed request reading as "not ready yet" rather than an error.
zk_is_writeable() {
  local response
  response=$(curl -sS --connect-timeout 2 --max-time 5 \
    "http://$ZK_HOST:$ZK_ADMIN_PORT/commands/is_read_only" 2>/dev/null) || return 1

  echo "$response" | grep -q '"read_only"[[:space:]]*:[[:space:]]*false'
}

wait_for_zookeeper_port() {
  local i
  for ((i=1; i<=ZK_WAIT_ATTEMPTS; i++)); do
    if zk_port_is_open; then
      echo "Zookeeper is available"
      return 0
    fi

    echo "Waiting for zookeeper"
    sleep "$ZK_WAIT_INTERVAL"
  done

  echo "Timed out waiting for zookeeper at $ZK_HOST:$ZK_CLIENT_PORT" >&2
  exit 1
}

wait_for_zookeeper_writeable() {
  local i
  for ((i=1; i<=ZK_WAIT_ATTEMPTS; i++)); do
    if zk_is_writeable; then
      echo "Zookeeper is writeable"
      return 0
    fi

    echo "Waiting for zookeeper to be writeable"
    sleep "$ZK_WAIT_INTERVAL"
  done

  echo "Timed out waiting for zookeeper to become writeable at $ZK_HOST:$ZK_ADMIN_PORT" >&2
  exit 1
}

# nc ships in the FID image today, but if that ever changes the wait loop would spin forever
# on a 127 exit code instead of reporting the problem
if ! command -v nc > /dev/null 2>&1; then
  echo "nc is not available, cannot probe zookeeper" >&2
  exit 1
fi

wait_for_zookeeper_port
wait_for_zookeeper_writeable

echo "Preparing FID"

if [ ! -d /var/secrets ]; then
  mkdir -p /var/secrets
fi

echo "$RADIANT_LICENSE" > /var/secrets/fid-license
echo "$ZK_PASSWORD" > /var/secrets/zk-password
echo "$ZK_USERNAME" > /var/secrets/zk-username
echo "$FID_ADMIN_API_KEY" > /var/secrets/fid-admin-api-key
echo "$FID_ROOT_USERNAME" > /var/secrets/fid-root-username
echo "$FID_ROOT_PASSWORD" > /var/secrets/fid-root-password

if [ -e "/opt/radiantone/vds/vds_server/license.lic" ] ; then
  # If license is mounted
  if [ -e "/var/secrets/fid-license" ] ; then
    LICENSE=$(cat /var/secrets/fid-license)
    OLD_LICENSE=$(cat /opt/radiantone/vds/vds_server/license.lic)
    # If license passed is different from old license
    if [ "$LICENSE" != "$OLD_LICENSE" ] ;  then
      echo "License changed, updating it..."
      echo $LICENSE > /opt/radiantone/vds/vds_server/license.lic
    fi
  fi
fi

if [ "$USE_CONTROL_PANEL" != true ]; then
  sed -i 's/\/opt\/radiantone\/vds\/bin\/launchControlPanel\.sh//g' ./run.sh
  sed -i 's/Starting Control Panel process/Skipping Starting Control Panel process/g' ./run.sh
fi

echo "Starting FID"
./run.sh

echo "Post-start operations"
if [ $? == 0 ]; then
  if [ -e "/var/secrets/fid-admin-api-key" ] ; then
    FID_API_KEY=$(cat /var/secrets/fid-admin-api-key)
    # echo "Setting add-admin-api-key"
    /opt/radiantone/vds/bin/vdsconfig.sh add-admin-api-key -key "$FID_API_KEY" > /dev/null
    # echo "Setting add-api-service-account"
    /opt/radiantone/vds/bin/vdsconfig.sh add-api-service-account -pwd "$FID_API_KEY" > /dev/null
  fi
  # set saas value
  # echo "Setting saas value to false"
  /opt/radiantone/vds/bin/vdsconfig.sh set-property -name saas -value false > /dev/null
  # Post install script
  # Post start script
  tail -f /dev/null
fi