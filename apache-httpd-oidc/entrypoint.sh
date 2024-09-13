#!/command/with-contenv bash
# shellcheck shell=bash
set -eo pipefail

### Load Helper Methods ###
source /usr/local/bin/entrypoint-helper.sh

configure_server_name
configure_server_ports
configure_virtual_hosts
configure_oidc_protection

### Execute Apache HTTPD ###
# Cleanup any residual or pre-existing PID files
rm -f /var/run/apache2/apache2.pid
# Load the Apache HTTPD environment variables
[[ -f /etc/apache2/envvars ]] && source /etc/apache2/envvars
# Execute Apache HTTPD in the foreground
exec s6-setuidgid www-data apache2 -DFOREGROUND "${@}"
