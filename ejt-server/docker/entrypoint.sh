#!/bin/sh

TZ=${TZ:-UTC}

if [ -n "${PGID}" ] && [ "${PGID}" != "$(id -g ejt)" ]; then
  echo "Switching to PGID ${PGID}..."
  sed -i -e "s/^ejt:\([^:]*\):[0-9]*/ejt:\1:${PGID}/" /etc/group
  sed -i -e "s/^ejt:\([^:]*\):\([0-9]*\):[0-9]*/ejt:\1:\2:${PGID}/" /etc/passwd
fi
if [ -n "${PUID}" ] && [ "${PUID}" != "$(id -u ejt)" ]; then
  echo "Switching to PUID ${PUID}..."
  sed -i -e "s/^ejt:\([^:]*\):[0-9]*:\([0-9]*\)/ejt:\1:${PUID}:\2/" /etc/passwd
fi

echo "Setting timezone to ${TZ} ..."
ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
echo ${TZ} > /etc/timezone

if [ ! -z "$EJTSERVER_LICENSES" ]; then
echo "Inserting licenses from environment variable ..."
> /config/license.txt
for current_key in $(echo "${EJTSERVER_LICENSES}" | tr "," "\n"); do
  echo "${current_key}" >> /config/license.txt
done
unset EJTSERVER_LICENSES
fi

if [ ! -f "/config/license.txt" ]; then
  echo "ERROR: No licenses defined. Define licenses with the EJTSERVER_LICENSES environment variable"
  exit 1
fi

if [ ! -z "$EJTSERVER_SERVER_KEY" ] && [ ! -z "$EJTSERVER_CLIENT_KEY" ]  && [ ! -z "$EJTSERVER_ADMIN_KEY" ]; then
  echo "Configuring encryption from environment variables ..."
  cat > /config/keys.env <<EOL
EJTSERVER_SERVER_KEY=${EJTSERVER_SERVER_KEY}
EJTSERVER_CLIENT_KEY=${EJTSERVER_CLIENT_KEY}
EJTSERVER_ADMIN_KEY=${EJTSERVER_ADMIN_KEY}
EOL
fi

unset EJTSERVER_SERVER_KEY
unset EJTSERVER_CLIENT_KEY
unset EJTSERVER_ADMIN_KEY

echo "Updating permissions..."
chown -R ejt:ejt /config /opt/ejtserver

exec su-exec ejt:ejt "$@"
