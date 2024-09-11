########################################################################################################################
#
# Define Global Build Arguments
#
########################################################################################################################
ARG UBUNTU_TAG="noble-20240801"
ARG S6_OVERLAY_VERSION="3.2.0.0"
ARG APACHE_HTTPD_VERSION="2.4.58-1ubuntu8.4"
ARG APACHE_HTTPD_MOD_OIDC_VERSION="2.4.15.1-1build3"
ARG GCS_FUSE_VERSION="2.4.0"
ARG SOURCE_DATE_EPOCH="0"

########################################################################################################################
#
# Setup S6 Overlay Base Layer
#
########################################################################################################################
FROM ubuntu:${UBUNTU_TAG} AS operating-system-base-interim
# Define Build Arguments
ARG SOURCE_DATE_EPOCH
ARG S6_OVERLAY_VERSION
ARG APACHE_HTTPD_VERSION
ARG APACHE_HTTPD_MOD_OIDC_VERSION
ARG GCS_FUSE_VERSION

# Define Standard Environment Variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install basic OS utilities & Apache2
RUN --mount=type=bind,source=./repro-sources-list.sh,target=/usr/local/bin/repro-sources-list.sh \
    repro-sources-list.sh && \
    apt-get update && \
    apt-get install --yes --no-install-recommends tar gzip zlib1g xz-utils curl ca-certificates tzdata \
                                                  apache2=${APACHE_HTTPD_VERSION} apache2-bin=${APACHE_HTTPD_VERSION} \
                                                  apache2-data=${APACHE_HTTPD_VERSION} apache2-utils=${APACHE_HTTPD_VERSION} \
                                                  libapache2-mod-auth-openidc=${APACHE_HTTPD_MOD_OIDC_VERSION}

# Install the GCS FUSE driver software
RUN ARCH="$(dpkg --print-architecture)" && \
    curl -sSLO https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v${GCS_FUSE_VERSION}/gcsfuse_${GCS_FUSE_VERSION}_${ARCH}.deb && \
    apt-get install --yes --no-install-recommends ./gcsfuse_${GCS_FUSE_VERSION}_${ARCH}.deb && \
    rm -f gcsfuse_${GCS_FUSE_VERSION}_${ARCH}.deb


###########################
####    S6 Install     ####
###########################
RUN set -eux; \
        NOARCH_PKG_ESUM="4b0c0907e6762814c31850e0e6c6762c385571d4656eb8725852b0b1586713b6" \
        NOARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        ARCH="$(dpkg --print-architecture)"; \
        case "${ARCH}" in \
           aarch64|arm64) \
             ARCH_PKG_ESUM='868973e98210257bba725ff5b17aa092008c9a8e5174499e38ba611a8fc7e473'; \
             ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-aarch64.tar.xz"; \
             ;; \
          amd64|i386:x86-64) \
            ARCH_PKG_ESUM='ad982a801bd72757c7b1b53539a146cf715e640b4d8f0a6a671a3d1b560fe1e2'; \
            ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz"; \
            ;; \
           ppc64el|powerpc:common64) \
             ARCH_PKG_ESUM='a5548e188e788c0bbf480c525cc08d1a6ce369a8e3aa113d7ac038f3da0c73d0'; \
             ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-powerpc64le.tar.xz"; \
             ;; \
           *) \
             echo "Unsupported arch: ${ARCH}"; \
             exit 1; \
             ;; \
        esac; \
    curl -sSLo /tmp/s6-overlay-noarch.tar.xz ${NOARCH_BINARY_URL}; \
    curl -sSLo /tmp/s6-overlay-arch.tar.xz ${ARCH_BINARY_URL}; \
    echo "${NOARCH_PKG_ESUM} */tmp/s6-overlay-noarch.tar.xz" | sha256sum -c -; \
    echo "${ARCH_PKG_ESUM} */tmp/s6-overlay-arch.tar.xz" | sha256sum -c -; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz; \
    rm -f /tmp/s6-overlay-noarch.tar.xz; \
    rm -f /tmp/s6-overlay-arch.tar.xz

# Add the s6 init configuration files
RUN mkdir -p /etc/s6-overlay/s6-rc.d/
COPY s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# Remove Unneeded Utilities
RUN --mount=type=bind,source=./repro-sources-list.sh,target=/usr/local/bin/repro-sources-list.sh \
    repro-sources-list.sh && \
    apt-get remove --yes xz-utils curl && \
    apt-get autoremove --yes && \
    apt-get autoclean --yes && \
    apt-get clean all --yes && \
    rm -rf /var/log/ && \
    rm -rf /var/cache/


########################################
####    Deterministic Build Hack    ####
########################################

# === Workarounds below will not be needed when https://github.com/moby/buildkit/pull/4057 is merged ===
# NOTE: PR #4057 has been merged but will not be available until the v0.13.x series of releases.
# Limit the timestamp upper bound to SOURCE_DATE_EPOCH.
# Workaround for https://github.com/moby/buildkit/issues/3180
RUN find $( ls / | grep -E -v "^(dev|mnt|proc|sys)$" ) \
  -newermt "@${SOURCE_DATE_EPOCH}" -writable -xdev \
  | xargs touch --date="@${SOURCE_DATE_EPOCH}" --no-dereference

FROM scratch AS operating-system-base
COPY --from=operating-system-base-interim / /

########################################################################################################################
#
# Setup Production Container Interim Image
#
########################################################################################################################
FROM operating-system-base AS production-image-interim
# Define Build Arguments
ARG SOURCE_DATE_EPOCH

# Define Standard Environment Variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Add the entrypoint script
ADD entrypoint.sh /usr/local/bin/
ADD entrypoint-helper.sh /usr/local/bin/
ADD logger.sh /usr/local/bin/

# Add the HTTPD configuration
COPY sites-available/ /etc/apache2/sites-available/
COPY conf-available/ /etc/apache2/conf-available/

# Configure the container
RUN --mount=type=bind,source=./configure-container.sh,target=/usr/local/bin/configure-container.sh configure-container.sh

########################################
####    Deterministic Build Hack    ####
########################################

# === Workarounds below will not be needed when https://github.com/moby/buildkit/pull/4057 is merged ===
# NOTE: PR #4057 has been merged but will not be available until the v0.13.x series of releases.
# Limit the timestamp upper bound to SOURCE_DATE_EPOCH.
# Workaround for https://github.com/moby/buildkit/issues/3180
RUN find $( ls / | grep -E -v "^(dev|mnt|proc|sys)$" ) \
  -newermt "@${SOURCE_DATE_EPOCH}" -writable -xdev \
  | xargs touch --date="@${SOURCE_DATE_EPOCH}" --no-dereference

########################################################################################################################
#
# Setup Production Container Final Image
#
########################################################################################################################
FROM scratch AS production-image
COPY --from=production-image-interim / /

# Define Standard Environment Variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Define Apache Environment Variables
ENV APACHE_CONFDIR=/etc/apache2
ENV HTTPD_DETECT_GLOBAL_SERVER_NAME=1
ENV HTTPD_RENDER_SITE_CONFIG=1
ENV HTTPD_SITE_ROOT_PATH=/var/www/html
ENV HTTPD_SITE_SSL_ENABLED=0

# Define OpenID Connect Environment Variables
ENV OIDC_AUTH_ENABLED=0
ENV OIDC_REDIRECT_URI=/.oidc-redirect

# Define GCS FUSE Environment Variables
ENV GCS_FUSE_ENABLED=0

EXPOSE 8080/tcp 8443/tcp

WORKDIR "/etc/apache2"
ENTRYPOINT ["/init", "/usr/local/bin/entrypoint.sh"]
