#!/usr/bin/env bash

### Import the Logger Library ###
source /usr/local/bin/logger.sh

########################################
####    Constants                   ####
########################################

readonly ICMPULSE_WORKING_DIRECTORY="/var/run/icmpulse"
readonly ICMPULSE_WORKING_CONF_FILE="${ICMPULSE_WORKING_DIRECTORY}/config.yaml"
readonly ICMPULSE_WORKING_TARGETS_FILE="${ICMPULSE_WORKING_DIRECTORY}/targets.json"

readonly ICMPULSE_CONF_DIRECTORY="/etc/icmpulse"
readonly ICMPULSE_CONF_TARGETS_FILE="${ICMPULSE_CONF_DIRECTORY}/targets.json"
readonly ICMPULSE_CONF_STAGING_FILE="${ICMPULSE_CONF_DIRECTORY}/config.yaml"
readonly ICMPULSE_CONF_TEMPLATE="${ICMPULSE_CONF_DIRECTORY}/config.tpl.yaml"

readonly KUBE_SERVICE_ACCOUNT_TOKEN="/var/run/secrets/kubernetes.io/serviceaccount/token"

readonly GOMPLATE="/usr/local/bin/gomplate"
readonly KUBECTL="/usr/local/bin/kubectl"
readonly JQ="/usr/bin/jq"

########################################
####    Global Configuration        ####
########################################
# Web Server Configuration
export ICMPULSE_WEB_LISTEN_ADDRESS ICMPULSE_WEB_TELEMETRY_PATH

# Ping Exporter Configuration
export ICMPULSE_PING_INTERVAL ICMPULSE_PING_TIMEOUT ICMPULSE_PING_SIZE ICMPULSE_PING_HISTORY_SIZE

# DNS Configuration
export ICMPULSE_DNS_REFRESH

# Logging Configuration
export ICMPULSE_LOG_LEVEL

# Targets Configuration
export ICMPULSE_TARGETS_JSON_FILE ICMPULSE_TARGETS_JSON_CONTENT

# ICMPulse Configuration File
export ICMPULSE_CONFIG_FILE ICMPULSE_CONFIG_CONTENT

# ICMPulse Optional Features
export ICMPULSE_K8S_NODE_INCLUDE_HOSTNAME ICMPULSE_BOOTSTRAP_SET_UID_GID

# Kubernetes Configuration
export KUBECONFIG

########################################
####    Helper Methods              ####
########################################

function truthy() {
  local value="${1}"

  if [[ -n "${value}" ]] && [[ "${value}" -ge 1 || "${value,,}" == "true" || "${value,,}" == "yes" || "${value,,}" == "on" ]]; then
    return 0
  fi

  return 1
}

function configure_targets() {
  export ICMPULSE_TARGETS_JSON_FILE
  export ICMPULSE_TARGETS_JSON_CONTENT

  local ec=0

  log.notice "configure_targets(): configuring targets from environment variables"

  if [[ -n "${ICMPULSE_CONFIG_FILE}" ]]; then
    log.success "configure_targets(): skipping target configuration, custom configuration file [${ICMPULSE_CONFIG_FILE}] provided"
    return 0
  fi

  if [[ -n "${ICMPULSE_TARGETS_JSON_FILE}" && -f "${ICMPULSE_TARGETS_JSON_FILE}" ]]; then
    log.notice "configure_targets(): located existing targets json file [${ICMPULSE_TARGETS_JSON_FILE}]"
    set +e
    cp -f "${ICMPULSE_TARGETS_JSON_FILE}" "${ICMPULSE_CONF_TARGETS_FILE}" >/dev/null 2>&1
    ec="${?}"
    set -e

    if [[ "${ec}" -ne 0 ]]; then
      log.error "configure_targets(): failed to copy existing targets json file [${ICMPULSE_TARGETS_JSON_FILE}] to config directory targets file [${ICMPULSE_CONF_TARGETS_FILE}]"
      return "${ec}"
    fi

    log.success "configure_targets(): successfully copied targets json file to config directory"
    return 0
  fi

  if [[ -n "${ICMPULSE_TARGETS_JSON_CONTENT}" ]]; then
    log.notice "configure_targets(): rendering targets from inline json environment variable"
    set +e
    printf "%s\n" "${ICMPULSE_TARGETS_JSON_CONTENT}" | tee "${ICMPULSE_CONF_TARGETS_FILE}" >/dev/null 2>&1
    ec="${?}"
    set -e

    if [[ "${ec}" -ne 0 ]]; then
      log.error "configure_targets(): failed to write targets json content to config directory targets file [${ICMPULSE_CONF_TARGETS_FILE}]"
      return "${ec}"
    fi

    log.success "configure_targets(): successfully rendered targets json content to config directory"
    return 0
  fi

  log.notice "configure_targets(): no targets json file or content provided, attempting to configure from kubernetes introspection"
  set +e
  configure_targets_from_kubernetes
  ec="${?}"
  set -e

  if [[ "${ec}" -eq 0 ]]; then
    log.success "configure_targets(): successfully configured targets from kubernetes introspection"
    return 0
  else
    log.warning "configure_targets(): unable to configure targets from kubernetes introspection (exit code: ${ec})"
  fi

  log.error "configure_targets(): failed to configure targets, no valid targets located"
  return "${ec}"
}

function configure_targets_from_kubernetes() {
  export KUBECONFIG
  export ICMPULSE_K8S_NODE_INCLUDE_HOSTNAME
  local ec=0

  log.notice "configure_targets_from_kubernetes(): configuring targets via kubernetes introspection"

  if [[ -z "${KUBECONFIG}" && ! -f "${KUBE_SERVICE_ACCOUNT_TOKEN}" ]]; then
    log.warning "configure_targets_from_kubernetes(): no service account token found at [${KUBE_SERVICE_ACCOUNT_TOKEN}] and no kubernetes environment variables found"
    return 1
  fi

  local nodes_list
  nodes_list="$(${KUBECTL} get nodes -o json | ${JQ} '.items')"
  ec="${?}"

  if [[ "${ec}" -ne 0 ]]; then
    log.error "configure_targets_from_kubernetes(): failed to enumerate kubernetes nodes, please verify the service account RBAC configuration (exit code: ${ec})"
    return 2
  fi

  if [[ -z "${nodes_list}" || "${nodes_list}" == "[]" ]]; then
    log.warning "configure_targets_from_kubernetes(): no kubernetes nodes found, skipping target configuration"
    return 3
  fi

  local query=". | map({ labels: {nodename: .metadata.name, target_type: \"internal\"}, address: .status.addresses[] | select(.type == \"InternalIP\") | .address })"

  if truthy "${ICMPULSE_K8S_NODE_INCLUDE_HOSTNAME}"; then
    query="${query} + map({ labels: {nodename: .metadata.name, target_type: \"external\"}, address: .status.addresses[] | select(.type == \"Hostname\") | .address })"
  fi

  ${JQ} -r "${query}" <<< "${nodes_list}" | \
    tee "${ICMPULSE_CONF_TARGETS_FILE}" >/dev/null 2>&1
  ec="${?}"

  if [[ "${ec}" -ne 0 ]]; then
    log.error "configure_targets_from_kubernetes(): failed to write kubernetes nodes to working directory targets file [${ICMPULSE_WORKING_TARGETS_FILE}]"
    return 4
  fi

  log.success "configure_targets_from_kubernetes(): successfully configured targets from kubernetes nodes"
  return 0
}

function configure_exporter() {
  export ICMPULSE_CONFIG_FILE
  export ICMPULSE_CONFIG_CONTENT

  log.notice "configure_exporter(): configuring icmpulse exporter"

  local ec=0

  if [[ -n "${ICMPULSE_CONFIG_FILE}" ]]; then
    log.notice "configure_exporter(): using custom configuration file [${ICMPULSE_CONFIG_FILE}]"

    if [[ ! -f "${ICMPULSE_CONFIG_FILE}" ]]; then
      log.error "configure_exporter(): custom configuration file [${ICMPULSE_CONFIG_FILE}] does not exist"
      return 1
    fi

    set +e
    cp -f "${ICMPULSE_CONFIG_FILE}" "${ICMPULSE_CONF_STAGING_FILE}" >/dev/null 2>&1
    ec="${?}"
    set -e

    if [[ "${ec}" -ne 0 ]]; then
      log.error "configure_exporter(): failed to copy custom configuration file [${ICMPULSE_CONFIG_FILE}] to config directory file [${ICMPULSE_CONF_STAGING_FILE}]"
      return "${ec}"
    fi

    log.success "configure_exporter(): successfully copied custom configuration file to config directory"
    return 0
  fi

  if [[ -n "${ICMPULSE_CONFIG_CONTENT}" ]]; then
    log.notice "configure_exporter(): rendering configuration from inline environment variable"
    set +e
    printf "%s\n" "${ICMPULSE_CONFIG_CONTENT}" | tee "${ICMPULSE_CONF_STAGING_FILE}" >/dev/null 2>&1
    ec="${?}"
    set -e

    if [[ "${ec}" -ne 0 ]]; then
      log.error "configure_exporter(): failed to write configuration content to config directory file [${ICMPULSE_CONF_STAGING_FILE}]"
      return "${ec}"
    fi

    log.success "configure_exporter(): successfully rendered configuration content to config directory"
    return 0
  fi

  log.notice "configure_exporter(): no custom configuration file or content provided, generating configuration from template"
  set +e
  generate_exporter_config
  ec="${?}"
  set -e

  if [[ "${ec}" -eq 0 ]]; then
    log.success "configure_exporter(): successfully generated exporter configuration from template"
    return 0
  fi

  log.error "configure_exporter(): unable to configure exporter, no valid configuration available"
  return "${ec}"
}

function generate_exporter_config() {
  log.notice "generate_exporter_config(): generating exporter configuration from template"

  if [[ ! -f "${ICMPULSE_CONF_TARGETS_FILE}" ]]; then
    log.error "generate_exporter_config(): targets file [${ICMPULSE_CONF_TARGETS_FILE}] does not exist, cannot generate exporter configuration"
    return 1
  fi

  set -x
  ${GOMPLATE} -c targets=file://${ICMPULSE_CONF_TARGETS_FILE} -f "${ICMPULSE_CONF_TEMPLATE}" -o "${ICMPULSE_CONF_STAGING_FILE}" >/dev/null 2>&1
  local ec="${?}"
  set +x

  if [[ "${ec}" -ne 0 ]]; then
    log.error "generate_exporter_config(): failed to generate exporter configuration from template (exit code: ${ec})"
    return "${ec}"
  fi

  log.notice "generate_exporter_config(): successfully generated exporter configuration"
  return 0
}

function load_configuration() {
  export ICMPULSE_CONFIG_FILE

  local ec=0
  log.notice "load_configuration(): loading icmpulse configuration"

  if [[ ! -f "${ICMPULSE_CONF_STAGING_FILE}" ]]; then
    log.error "load_configuration(): configuration file [${ICMPULSE_CONF_STAGING_FILE}] does not exist, cannot load configuration"
    return 1
  fi

  if [[ -z "${ICMPULSE_CONFIG_FILE}" ]]; then
    if [[ ! -f "${ICMPULSE_CONF_TARGETS_FILE}" ]]; then
      log.error "load_configuration(): targets file [${ICMPULSE_CONF_TARGETS_FILE}] does not exist, cannot load configuration"
      return 1
    fi

    set +e
    load_changed_file "${ICMPULSE_CONF_TARGETS_FILE}" "${ICMPULSE_WORKING_TARGETS_FILE}"
    ec="${?}"
    set -e

    if [[ "${ec}" -ge 2 ]]; then
      log.error "load_configuration(): failed to load targets file from [${ICMPULSE_CONF_TARGETS_FILE}] to [${ICMPULSE_WORKING_TARGETS_FILE}] (exit code: ${ec})"
      return "${ec}"
    fi

    log.success "load_configuration(): successfully loaded targets file to working directory [${ICMPULSE_WORKING_TARGETS_FILE}]"
  fi

  set +e
  load_changed_file "${ICMPULSE_CONF_STAGING_FILE}" "${ICMPULSE_WORKING_CONF_FILE}"
  ec="${?}"
  set -e

  if [[ "${ec}" -ge 2 ]]; then
    log.error "load_configuration(): failed to load configuration file from [${ICMPULSE_CONF_STAGING_FILE}] to [${ICMPULSE_WORKING_CONF_FILE}] (exit code: ${ec})"
    return "${ec}"
  fi

  log.success "load_configuration(): successfully loaded configuration file to working directory [${ICMPULSE_WORKING_CONF_FILE}]"
  return 0
}

function load_changed_file() {
  local source_file="${1}"
  local target_file="${2}"
  local ec=0

  log.notice "load_changed_file(): loading file from [${source_file}] to [${target_file}], if the file has changed"

  if [[ -z "${source_file}" || ! -f "${source_file}" ]]; then
    log.error "load_changed_file(): source file [${source_file}] is not set or does not exist"
    return 2
  fi

  if [[ -z "${target_file}" ]]; then
    log.error "load_changed_file(): target file path was not provided, but is required"
    return 2
  fi

  if [[ ! -f "${target_file}" ]]; then
    log.notice "load_changed_file(): target file [${target_file}] does not exist, copying source file to target"
    cp -f "${source_file}" "${target_file}" >/dev/null 2>&1
    ec="${?}"

    if [[ "${ec}" -ne 0 ]]; then
      log.error "load_changed_file(): failed to copy source file [${source_file}] to target file [${target_file}] (exit code: ${ec})"
      return 2
    fi

    log.notice "load_changed_file(): successfully loaded source file [${source_file}] to target file [${target_file}]"
    return 1
  fi

  local diff_ec=0
  diff -q "${source_file}" "${target_file}" >/dev/null 2>&1
  diff_ec="${?}"

  if [[ "${diff_ec}" -ge 2 ]]; then
    log.error "load_changed_file(): failed to compare source file [${source_file}] with target file [${target_file}] (exit code: ${diff_ec})"
    return 2
  elif [[ "${diff_ec}" -eq 1 ]]; then
    log.notice "load_changed_file(): source file [${source_file}] differs from target file [${target_file}], copying source file to target"
    cp -f "${source_file}" "${target_file}" >/dev/null 2>&1
    ec="${?}"

    if [[ "${ec}" -ne 0 ]]; then
      log.error "load_changed_file(): failed to copy source file [${source_file}] to target file [${target_file}] (exit code: ${ec})"
      return 2
    fi

    log.notice "load_changed_file(): successfully loaded source file [${source_file}] to target file [${target_file}]"
    return 1
  fi

  log.notice "load_changed_file(): source file [${source_file}] is identical to target file [${target_file}], no changes made"
  return 0
}

function with_context() {
  local s6_command="s6-setuidgid icmpulse"

  set +e
  if truthy "${ICMPULSE_BOOTSTRAP_SET_UID_GID}"; then
    s6_command="s6-setuidgid icmpulse"
  else
    s6_command=""
  fi
  set -e

  if [[ -n "${s6_command}" ]]; then
    log.notice "exec_with_context(): executing command in the icmpulse user context [ ${*} ]"
    exec ${s6_command} "${@}"
  else
    log.notice "exec_with_context(): executing command without the icmpulse user context [ ${*} ]"
    exec "${@}"
  fi
}

function ping_exporter_args() {
  local argv=""

  [[ -n "${ICMPULSE_WEB_LISTEN_ADDRESS}" ]] && argv="--web.listen-address '${ICMPULSE_WEB_LISTEN_ADDRESS}'"
  [[ -n "${ICMPULSE_WEB_TELEMETRY_PATH}" ]] && argv="${argv} --web.telemetry-path '${ICMPULSE_WEB_TELEMETRY_PATH}'"
  [[ -n "${ICMPULSE_LOG_LEVEL}" ]] && argv="${argv} --log.level ${ICMPULSE_LOG_LEVEL}"

  printf "%s" "${argv}" | tr -d '[:space:]'
  return 0
}
