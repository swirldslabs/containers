#!/usr/bin/env bash

### Import the Logger Library ###
source /usr/local/bin/logger.sh

########################################
####    Constants                   ####
########################################

readonly HTTPD_CONF_DIRECTORY="/etc/apache2"
readonly GCS_FUSE_RUN_DIRECTORY="/var/run/gcsfuse-credentials"

########################################
####    Global Configuration        ####
########################################
# Server Names
export HTTPD_GLOBAL_SERVER_NAME HTTPD_DETECT_GLOBAL_SERVER_NAME

# Options Configuration
export HTTPD_RENDER_SITE_CONFIG

# Site Configuration
export HTTPD_SITE_ROOT_PATH HTTPD_SITE_SERVER_NAME HTTPD_SITE_ADMIN_EMAIL HTTPD_SITE_DIRECTORY_INDEX

# SSL Support
export HTTPD_SITE_HTTP_PORT HTTPD_SITE_HTTPS_PORT
export HTTPD_SITE_SSL_ENABLED HTTPD_SITE_SSL_REDIRECT_ENABLED
export HTTPD_SITE_SSL_CERT_FILE HTTPD_SITE_SSL_KEY_FILE HTTPD_SITE_CA_FILE

# OIDC Support
export OIDC_AUTH_ENABLED OIDC_PROVIDER_METADATA_URL OIDC_CLIENT_ID OIDC_REDIRECT_URI
export OIDC_CLIENT_SECRET OIDC_CRYPTO_PASSPHRASE
export OIDC_SCOPE OIDC_REMOTE_USER_CLAIM

# GCSFuse Support
export GCS_FUSE_ENABLED GCS_FUSE_CONFIG_FILE GCS_FUSE_BUCKET_NAME GCS_FUSE_MOUNT_POINT
export GCS_FUSE_INODE_UID GCS_FUSE_INODE_GID GCS_FUSE_EXTRA_OPTS
export GCS_FUSE_JWT_CREDENTIALS GOOGLE_APPLICATION_CREDENTIALS

########################################
####    Helper Methods              ####
########################################

function execute_gcs_fuse_driver {
  export GCS_FUSE_ENABLED GCS_FUSE_CONFIG_FILE GCS_FUSE_BUCKET_NAME GCS_FUSE_MOUNT_POINT
  export GCS_FUSE_INODE_UID GCS_FUSE_INODE_GID GCS_FUSE_EXTRA_OPTS
  export GCS_FUSE_JWT_CREDENTIALS GOOGLE_APPLICATION_CREDENTIALS

  [[ -z "${GCS_FUSE_MOUNT_POINT}" ]] && GCS_FUSE_MOUNT_POINT="/var/www/html"
  [[ -z "${GCS_FUSE_INODE_UID}" ]] && GCS_FUSE_INODE_UID=33
  [[ -z "${GCS_FUSE_INODE_GID}" ]] && GCS_FUSE_INODE_GID=33

  [[ -f "${GCS_FUSE_MOUNT_POINT}" ]] || mkdir -p "${GCS_FUSE_MOUNT_POINT}" >/dev/null 2>&1

  local args=("--foreground" "--uid" "${GCS_FUSE_INODE_UID}" "--gid" "${GCS_FUSE_INODE_GID}" "-o" "ro,allow_other" "--implicit-dirs")
  [[ -n "${GCS_FUSE_CONFIG_FILE}" && -f "${GCS_FUSE_CONFIG_FILE}" ]] && args+=("--config-file" "${GCS_FUSE_CONFIG_FILE}")

  # If GCS Fuse Support is disabled then we should sleep indefinitely
  if [[ "${GCS_FUSE_ENABLED}" != true && "${GCS_FUSE_ENABLED}" -lt 1 ]]; then
    log.notice "execute_gcs_fuse_driver(): gcs-fuse support is disabled, entering service sleep"
    /usr/bin/sleep infinity
    return "0"
  fi

  if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS}" && -z "${GCS_FUSE_JWT_CREDENTIALS}" ]]; then
    log.error "execute_gcs_fuse_driver(): No credentials were provided via GOOGLE_APPLICATION_CREDENTIALS or GCS_FUSE_JWT_CREDENTIALS variables"
    return "1"
  fi

  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS}" && ! -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    log.error "execute_gcs_fuse_driver(): Credentials file path was provided, but the file cannot be found [${GOOGLE_APPLICATION_CREDENTIALS}]"
    return "1"
  fi

  if [[ -n "${GCS_FUSE_JWT_CREDENTIALS}" ]]; then
    mkdir -p "${GCS_FUSE_RUN_DIRECTORY}" >/dev/null 2>&1 || return "${?}"
    tee "${GCS_FUSE_RUN_DIRECTORY}/adc.json" <<<"${GCS_FUSE_JWT_CREDENTIALS}" >/dev/null || return "${?}"
    log.notice "execute_gcs_fuse_driver(): Credentials loaded from supplied JWT variable [${GCS_FUSE_RUN_DIRECTORY}/adc.json]"
    args+=("--key-file" "${GCS_FUSE_RUN_DIRECTORY}/adc.json")
  else
    log.notice "execute_gcs_fuse_driver(): Credentials loaded from supplied GOOGLE_APPLICATION_CREDENTIALS variable [${GOOGLE_APPLICATION_CREDENTIALS}]"
    args+=("--key-file" "${GOOGLE_APPLICATION_CREDENTIALS}")
  fi

  if [[ -n "${GCS_FUSE_EXTRA_OPTS}" ]]; then
    /usr/bin/gcsfuse "${args[@]}" "${GCS_FUSE_EXTRA_OPTS}" "${GCS_FUSE_BUCKET_NAME}" "${GCS_FUSE_MOUNT_POINT}"
    return "${?}"
  fi

  /usr/bin/gcsfuse "${args[@]}" "${GCS_FUSE_BUCKET_NAME}" "${GCS_FUSE_MOUNT_POINT}"
  return "${?}"
}

function configure_server_ports {
  export HTTPD_SITE_HTTP_PORT HTTPD_SITE_HTTP_PORT
  local provided="false"

  if [[ -z "${HTTPD_SITE_HTTP_PORT}" || "${HTTPD_SITE_HTTP_PORT}" -le 0 || "${HTTPD_SITE_HTTP_PORT}" -ge 65536 ]]; then
    log.warning "Defaulting the HTTPD_SITE_HTTP_PORT variable because no reasonable value was provided [8080]"
    HTTPD_SITE_HTTP_PORT="8080"
  else
    log.notice "Configuring the HTTP port with the supplied value [${HTTPD_SITE_HTTP_PORT}]"
    provided="true"
  fi

  if [[ -z "${HTTPD_SITE_HTTPS_PORT}" || "${HTTPD_SITE_HTTPS_PORT}" -le 0 || "${HTTPD_SITE_HTTPS_PORT}" -ge 65536 ]]; then
    log.warning "Defaulting the HTTPD_SITE_HTTPS_PORT variable because no reasonable value was provided [8443]"
    HTTPD_SITE_HTTPS_PORT="8443"
  else
    log.notice "Configuring the HTTPS port with the supplied value [${HTTPD_SITE_HTTPS_PORT}]"
    provided="true"
  fi

  if [[ "${provided}" == true ]]; then
    log.notice "Rewriting HTTPD ports configuration [${HTTPD_SITE_HTTP_PORT}/http, ${HTTPD_SITE_HTTPS_PORT}/https]"
    # Rewrite ports.conf to use 8080 & 8443
    </etc/apache2/ports.conf \
      perl -pe "s/Listen\s+8080/Listen ${HTTPD_SITE_HTTP_PORT}/g" | \
      perl -pe "s/Listen\s+8443/Listen ${HTTPD_SITE_HTTPS_PORT}/g" | \
      tee /etc/apache2/ports.conf.tmp >/dev/null
    cp -f /etc/apache2/ports.conf.tmp /etc/apache2/ports.conf
    rm -f /etc/apache2/ports.conf.tmp
  fi

  return "0"
}

function configure_server_name {
  export HTTPD_GLOBAL_SERVER_NAME HTTPD_DETECT_GLOBAL_SERVER_NAME
  local enabled="false"
  local detect="false"

  [[ -n "${HTTPD_GLOBAL_SERVER_NAME}" ]] && enabled="true"
  [[ "${HTTPD_DETECT_GLOBAL_SERVER_NAME}" == true || "${HTTPD_DETECT_GLOBAL_SERVER_NAME}" -gt 0 ]] && detect="true"

  if [[ "${detect}" == true && -z "${HTTPD_GLOBAL_SERVER_NAME}" ]]; then
    HTTPD_GLOBAL_SERVER_NAME="$(hostname --fqdn)"
    enabled="true"
  fi

  if [[ "${enabled}" == true ]]; then
    log.notice "Configuring the global server name [${HTTPD_GLOBAL_SERVER_NAME}]"
    a2enconf global-server-name >/dev/null
    return "${?}"
  fi

  return "0"
}

function configure_virtual_hosts {
  export HTTPD_RENDER_SITE_CONFIG HTTPD_SITE_ROOT_PATH HTTPD_SITE_DIRECTORY_INDEX

  if [[ "${HTTPD_RENDER_SITE_CONFIG}" != true && "${HTTPD_RENDER_SITE_CONFIG}" -lt 1 ]]; then
    log.warning "Site configuration rendering disabled"
    return "0"
  fi

  if [[ -z "${HTTPD_SITE_DIRECTORY_INDEX}" ]]; then
    log.notice "Directory index has been disabled by default, because the HTTPD_SITE_DIRECTORY_INDEX variable was not set"
    HTTPD_SITE_DIRECTORY_INDEX="disabled"
  else
    log.notice "Directory index support has been enabled, using user provided index file name [${HTTPD_SITE_DIRECTORY_INDEX}]"
  fi

  if [[ -z "${HTTPD_SITE_ROOT_PATH}" ]]; then
    log.warning "Defaulting the HTTPD_SITE_ROOT_PATH environment because none was provided"
    HTTPD_SITE_ROOT_PATH="/var/www/html"
  fi

  local site_config="default-nossl"
  if [[ "${HTTPD_SITE_SSL_ENABLED}" != true && "${HTTPD_SITE_SSL_ENABLED}" -lt 1 ]]; then
    log.notice "Loading the default non-SSL site configuration"
    site_config="default-nossl"
  else
    if [[ "${HTTPD_SITE_SSL_REDIRECT_ENABLED}" == true || "${HTTPD_SITE_SSL_REDIRECT_ENABLED}" -gt 0 ]]; then
      log.notice "Loading the default SSL with Redirection site configuration"
      site_config="default-ssl-redirect"
    else
      log.notice "Loading the default SSL site configuration"
      site_config="default-ssl"
    fi

    configure_site_ssl_ca_file "${site_config}" || return "${?}"
  fi

  a2ensite ${site_config} >/dev/null || return "${?}"
  configure_site_server_name "${site_config}" || return "${?}"
  configure_site_admin_email "${site_config}" || return "${?}"

  return "0"
}

function configure_oidc_protection {
  export OIDC_AUTH_ENABLED OIDC_SCOPE

  if [[ "${OIDC_AUTH_ENABLED}" != true && "${OIDC_AUTH_ENABLED}" -lt 1 ]]; then
    log.notice "Virtual host OIDC authentication is disabled"
    return "0"
  fi

  configure_oidc_remote_user_claim || return "${?}"

  if [[ -z "${OIDC_SCOPE}" ]]; then
    log.notice "Defaulting the OIDC_SCOPE variable, because no value was provided [openid email profile]"
    OIDC_SCOPE="openid email profile"
  else
    log.notice "Configuring the OIDC scope using the provided values [${OIDC_SCOPE}]"
  fi

  log.notice "Enabling OIDC authentication for the virtual host [${OIDC_PROVIDER_METADATA_URL}]"
  a2enmod auth_openidc >/dev/null || return "${?}"
  a2enconf oidc-provider >/dev/null
  return "${?}"
}

function configure_oidc_remote_user_claim {
  export OIDC_REMOTE_USER_CLAIM

  [[ -z "${OIDC_REMOTE_USER_CLAIM}" ]] && return "0"

  log.notice "Configuring the OIDC remote user claim [${OIDC_REMOTE_USER_CLAIM}]"
  local path="${HTTPD_CONF_DIRECTORY}/conf-available/oidc-provider.conf"
  uncomment_config_element "${path}" "OIDCRemoteUserClaim"
  return "${?}"
}

function configure_site_server_name {
  local config_name="${1}"
  export HTTPD_SITE_SERVER_NAME

  [[ -z "${HTTPD_SITE_SERVER_NAME}" ]] && return "0"

  if [[ -z "${config_name}" ]]; then
    log.error "configure_site_server_name(): Invalid Arguments - No config name provided"
    return "1"
  fi

  log.notice "Configuring the virtual host server name [${HTTPD_SITE_SERVER_NAME}]"
  local path="${HTTPD_CONF_DIRECTORY}/sites-available/${config_name}.conf"
  uncomment_config_element "${path}" "ServerName"
  return "${?}"
}

function configure_site_admin_email {
  local config_name="${1}"
  export HTTPD_SITE_ADMIN_EMAIL

  [[ -z "${HTTPD_SITE_ADMIN_EMAIL}" ]] && return "0"

  if [[ -z "${config_name}" ]]; then
    log.error "configure_site_admin_email(): Invalid Arguments - No config name provided"
    return "1"
  fi

  log.notice "Configuring the virtual host administrator email [${HTTPD_SITE_ADMIN_EMAIL}]"
  local path="${HTTPD_CONF_DIRECTORY}/sites-available/${config_name}.conf"
  uncomment_config_element "${path}" "ServerAdmin"
  return "${?}"
}

function configure_site_ssl_ca_file {
  local config_name="${1}"
  export HTTPD_SITE_CA_FILE

  [[ -z "${HTTPD_SITE_CA_FILE}" || ! -f "${HTTPD_SITE_CA_FILE}" ]] && return "0"

  if [[ -z "${config_name}" ]]; then
    log.error "configure_site_ssl_ca_file(): Invalid Arguments - No config name provided"
    return "1"
  fi

  log.notice "Configuring the virtual host SSL CA certificate [${HTTPD_SITE_CA_FILE}]"
  local path="${HTTPD_CONF_DIRECTORY}/sites-available/${config_name}.conf"
  uncomment_config_element "${path}" "SSLCACertificateFile"
  return "${?}"
}

function uncomment_config_element {
  local path="${1}"
  local element="${2}"

  local ec="0"

  if [[ ! -f "${path}" ]]; then
    log.error "uncomment_config_element(): Unable to locate the site configuration [${path}]"
    return "1"
  fi

  set +e
  <"${path}" perl -pe "s/#${element}/${element}/g" | tee "${path}.tmp" >/dev/null
  ec="${?}"
  set -e

  if [[ "${ec}" -ne 0 ]]; then
    log.error "uncomment_config_element(): Failed while writing temporary config [${path}.tmp]"
    rm -f "${path}.tmp" >/dev/null 2>&1
    return "1"
  fi

  set +e
  cp -f "${path}.tmp" "${path}" >/dev/null 2>&1 && rm -f "${path}.tmp" >/dev/null 2>&1
  ec="${?}"
  set -e

  if [[ "${ec}" -ne 0 ]]; then
    log.error "uncomment_config_element(): Failed while writing final config [${path}]"
    rm -f "${path}.tmp" >/dev/null 2>&1
    return "1"
  fi

  return "0"
}
