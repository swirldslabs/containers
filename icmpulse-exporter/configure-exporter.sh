#!/command/with-contenv bash
# shellcheck shell=bash
set -eo pipefail

### Load Helper Methods ###
source /usr/local/bin/entrypoint-helper.sh

### Configure ICMPulse Exporter ###
configure_targets
configure_exporter
load_configuration
