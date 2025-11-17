########################################################################################################################
#
# Define Global Build Arguments
#
########################################################################################################################
ARG OS_VERSION_TAG="bookworm-20250811-slim"
ARG S6_OVERLAY_VERSION="3.2.1.0"
ARG PING_EXPORTER_VERSION="1.1.3"
ARG GOMPLATE_VERSION="4.3.3"
ARG KUBERNETES_VERSION="1.33.3"
ARG SOURCE_DATE_EPOCH="0"

########################################################################################################################
#
# Setup S6 Overlay Base Layer
#
########################################################################################################################
FROM debian:${OS_VERSION_TAG} AS operating-system-base-interim
# Define Build Arguments
ARG SOURCE_DATE_EPOCH
ARG S6_OVERLAY_VERSION
ARG PING_EXPORTER_VERSION
ARG GOMPLATE_VERSION
ARG KUBERNETES_VERSION

# Define Standard Environment Variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install basic OS utilities & Apache2
RUN --mount=type=bind,source=./repro-sources-list.sh,target=/usr/local/bin/repro-sources-list.sh \
    repro-sources-list.sh && \
    apt-get update && \
    apt-get install --yes --no-install-recommends tar gzip zlib1g xz-utils curl ca-certificates tzdata jq libcap2-bin && \
    apt-get install --yes --no-install-recommends iputils-ping traceroute iputils-tracepath dnsutils mtr-tiny

###############################
####    KubeCtl Install    ####
###############################
RUN set -eux; \
        ARCH="$(dpkg --print-architecture)"; \
        case "${ARCH}" in \
          aarch64|arm64) \
            ARCH_PKG_ESUM='3d514dbae5dc8c09f773df0ef0f5d449dfad05b3aca5c96b13565f886df345fd'; \
            ARCH_BINARY_URL="https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/arm64/kubectl"; \
            ;; \
          amd64|i386:x86-64) \
            ARCH_PKG_ESUM='2fcf65c64f352742dc253a25a7c95617c2aba79843d1b74e585c69fe4884afb0'; \
            ARCH_BINARY_URL="https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"; \
            ;; \
           *) \
             echo "Unsupported arch: ${ARCH}"; \
             exit 1; \
             ;; \
        esac; \
        curl -sSLo /tmp/kubectl ${ARCH_BINARY_URL}; \
        echo "${ARCH_PKG_ESUM} /tmp/kubectl" | sha256sum -c -; \
        mv /tmp/kubectl /usr/local/bin/kubectl; \
        chmod +x /usr/local/bin/kubectl

################################
####    Gomplate Install    ####
################################
RUN set -eux; \
        ARCH="$(dpkg --print-architecture)"; \
        case "${ARCH}" in \
          aarch64|arm64) \
            ARCH_PKG_ESUM='25bd73720ff470cec0dfaa31ca2c436b30f86142db9af68382ce64e0f3e7b9c5'; \
            ARCH_BINARY_URL="https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}/gomplate_linux-arm64"; \
            ;; \
          amd64|i386:x86-64) \
            ARCH_PKG_ESUM='ca281666e86f2f09218c1653e1908f572c0e349e9de64cb4ea93ade9333f0596'; \
            ARCH_BINARY_URL="https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}/gomplate_linux-amd64"; \
            ;; \
           *) \
             echo "Unsupported arch: ${ARCH}"; \
             exit 1; \
             ;; \
        esac; \
        curl -sSLo /tmp/gomplate ${ARCH_BINARY_URL}; \
        echo "${ARCH_PKG_ESUM} /tmp/gomplate" | sha256sum -c -; \
        mv /tmp/gomplate /usr/local/bin/gomplate; \
        chmod +x /usr/local/bin/gomplate

######################################
####    Ping Exporter Install     ####
######################################
RUN set -eux; \
        ARCH="$(dpkg --print-architecture)"; \
        case "${ARCH}" in \
          aarch64|arm64) \
            ARCH_PKG_ESUM='6b299d775769fe6d938ac37d65972811370b0251f93f50fb6d392176ebbe4528'; \
            ARCH_BINARY_URL="https://github.com/czerwonk/ping_exporter/releases/download/${PING_EXPORTER_VERSION}/ping_exporter_${PING_EXPORTER_VERSION}_linux_arm64.tar.gz"; \
            ;; \
          amd64|i386:x86-64) \
            ARCH_PKG_ESUM='2423ed675b1024f013b637470324e8a1704a9a420b2760d3544e3d16d1d708de'; \
            ARCH_BINARY_URL="https://github.com/czerwonk/ping_exporter/releases/download/${PING_EXPORTER_VERSION}/ping_exporter_${PING_EXPORTER_VERSION}_linux_amd64.tar.gz"; \
            ;; \
           *) \
             echo "Unsupported arch: ${ARCH}"; \
             exit 1; \
             ;; \
        esac; \
        curl -sSLo /tmp/ping_exporter.tar.gz ${ARCH_BINARY_URL}; \
        echo "${ARCH_PKG_ESUM} /tmp/ping_exporter.tar.gz" | sha256sum -c -; \
        tar -C /usr/local/bin/ -xzf /tmp/ping_exporter.tar.gz ping_exporter; \
        rm -f /tmp/ping_exporter.tar.gz; \
        chmod +x /usr/local/bin/ping_exporter; \
        mkdir -p /etc/icmpulse/; \
        setcap 'cap_net_raw+ep' /usr/local/bin/ping_exporter

# Add the ping_exporter configuration template
ADD conf/config.tpl.yaml /etc/icmpulse/config.tpl.yaml

###########################
####    S6 Install     ####
###########################
RUN set -eux; \
        NOARCH_PKG_ESUM="42e038a9a00fc0fef70bf0bc42f625a9c14f8ecdfe77d4ad93281edf717e10c5" \
        NOARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        ARCH="$(dpkg --print-architecture)"; \
        case "${ARCH}" in \
           aarch64|arm64) \
             ARCH_PKG_ESUM='c8fd6b1f0380d399422fc986a1e6799f6a287e2cfa24813ad0b6a4fb4fa755cc'; \
             ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-aarch64.tar.xz"; \
             ;; \
          amd64|i386:x86-64) \
            ARCH_PKG_ESUM='8bcbc2cada58426f976b159dcc4e06cbb1454d5f39252b3bb0c778ccf71c9435'; \
            ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz"; \
            ;; \
           ppc64el|powerpc:common64) \
             ARCH_PKG_ESUM='4fe93725bf506926414608558e7402178437814001b9d93464e71686a4aa1260'; \
             ARCH_BINARY_URL="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-powerpc64le.tar.xz"; \
             ;; \
           *) \
             echo "Unsupported arch: ${ARCH}"; \
             exit 1; \
             ;; \
        esac; \
    curl -sSLo /tmp/s6-overlay-noarch.tar.xz ${NOARCH_BINARY_URL}; \
    curl -sSLo /tmp/s6-overlay-arch.tar.xz ${ARCH_BINARY_URL}; \
    echo "${NOARCH_PKG_ESUM} /tmp/s6-overlay-noarch.tar.xz" | sha256sum -c -; \
    echo "${ARCH_PKG_ESUM} /tmp/s6-overlay-arch.tar.xz" | sha256sum -c -; \
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
ADD entrypoint-helper.sh /usr/local/bin/
ADD logger.sh /usr/local/bin/
ADD configure-exporter.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/entrypoint-helper.sh && \
    chmod +x /usr/local/bin/logger.sh && \
    chmod +x /usr/local/bin/configure-exporter.sh

# Create the local user and group
RUN groupadd --gid 1000 icmpulse && \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --no-user-group --create-home icmpulse

# Update icmpulse configuration directory ownership
RUN chown -R icmpulse:icmpulse /etc/icmpulse/ && \
    chmod 755 /etc/icmpulse/ && \
    chmod 644 /etc/icmpulse/config.tpl.yaml

# Create the icmpulse var run directory
RUN mkdir -p /var/run/icmpulse && \
    chown -R icmpulse:icmpulse /var/run/icmpulse && \
    chmod 755 /var/run/icmpulse

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

ENV ICMPULSE_CONFIG_FILE=""
ENV ICMPULSE_CONFIG_CONTENT=""
ENV ICMPULSE_TARGETS_JSON_FILE=""
ENV ICMPULSE_TARGETS_JSON_CONTENT=""
ENV ICMPULSE_LOG_LEVEL="info"
ENV ICMPULSE_WEB_LISTEN_ADDRESS=":9100"
ENV ICMPULSE_WEB_TELEMETRY_PATH="metrics"
ENV ICMPULSE_PING_INTERVAL="10s"
ENV ICMPULSE_PING_TIMEOUT="5s"
ENV ICMPULSE_PING_SIZE="56"
ENV ICMPULSE_PING_HISTORY_SIZE="20"
ENV ICMPULSE_DNS_REFRESH="5m"
ENV ICMPULSE_K8S_NODE_INCLUDE_HOSTNAME="0"
ENV ICMPULSE_BOOTSTRAP_SET_UID_GID="1"

EXPOSE 9100/tcp

WORKDIR "/home/icmpulse"

ENTRYPOINT ["/init"]
