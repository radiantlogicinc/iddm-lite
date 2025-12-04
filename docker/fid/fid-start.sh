#!/usr/bin/env bash

# Not using bash strict mode because much of this is copied verbatim from existing code that does not use it

until nc -w 2 -z zookeeper 2181; do
  echo "Waiting for zookeeper"
  sleep 2
done

echo "Zookeeper is available"

until curl --silent http://zookeeper:8080/commands/is_read_only; do
  echo "Waiting for zookeeper to be writeable"
  sleep 5
done

echo "Zookeeper is writeable"

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