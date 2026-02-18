# Unified development Dockerfile for themed and standard builds
#
# Usage:
#  - Build a themed image:
#      docker build --build-arg KEYCLOAK_VERSION=26.5.1 --build-arg THEMED=true -t obp-keycloak:themed .
#  - Build a standard image (themes will be removed at the end):
#      docker build --build-arg KEYCLOAK_VERSION=26.5.1 --build-arg THEMED=false -t obp-keycloak:standard .
#
# Notes:
#  - The provider JAR must be pre-built on the host before running docker build
#    (see run-local-postgres-cicd.sh). No JDBC drivers are needed — authentication
#    goes through the OBP REST API, not direct database access.
#  - Keycloak version is parameterized with a build arg.
#  - THEMED controls whether theme files are retained in the final image. The Docker build
#    context must contain the `themes/` directories (the repository includes them).
#
# Build arguments (defaults chosen to match development state):
ARG KEYCLOAK_VERSION=26.5.1

ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# === Keycloak Builder Stage ===
FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} as builder

# Bring build args into this stage for cache invalidation metadata
ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# Enable useful Keycloak features
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange
ENV KC_DB=postgres

WORKDIR /opt/keycloak

# Need root temporarily for keystore generation and provider additions
USER root

# Generate a self-signed SSL certificate for development/testing (keystore path consistent with older Dockerfiles)
RUN keytool -genkeypair -storepass password -storetype PKCS12 \
    -keyalg RSA -keysize 2048 -dname "CN=server" -alias server \
    -ext "SAN:c=DNS:localhost,IP:127.0.0.1" \
    -keystore conf/server.keystore

# Write build metadata (previously generated inside the maven stage)
RUN echo "Build timestamp: ${BUILD_TIMESTAMP}" > /tmp/build-info.txt && \
    echo "JAR checksum: ${JAR_CHECKSUM}" >> /tmp/build-info.txt

# Copy the compiled provider jar from the host build
COPY --chown=keycloak:keycloak target/obp-keycloak-provider.jar /opt/keycloak/providers/

# Prebuild Keycloak (compile extensions, optimize)
RUN /opt/keycloak/bin/kc.sh build

# === Final Runtime Image ===
FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}

# Bring the prebuilt Keycloak server into the final image
COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY --from=builder /tmp/build-info.txt /opt/keycloak/

# Copy theme files (repository contains themes/obp and themes/obp-dark)
# The THEMED build arg controls whether themes are kept in the final image. Default is false.
USER root
ARG THEMED=false

# Copy themes if present in build context; repository provides these directories.
# If you want a build without themes, set --build-arg THEMED=false (themes will be removed later).
COPY themes/obp/ /opt/keycloak/themes/obp/
COPY themes/obp-dark/ /opt/keycloak/themes/obp-dark/

# Ensure correct owner for theme files
RUN chown -R keycloak:keycloak /opt/keycloak/themes/ || true

# If THEMED is false, remove theme files to produce a smaller standard image.
# Using a shell conditional ensures the build doesn't fail; presence of themes is expected in this repo.
RUN if [ "${THEMED}" = "false" ]; then rm -rf /opt/keycloak/themes/* || true; fi

# Copy the custom entrypoint wrapper that injects runtime ENV into theme config
COPY development/docker/docker-entrypoint.sh /opt/keycloak/docker-entrypoint.sh
RUN chmod 755 /opt/keycloak/docker-entrypoint.sh && chown keycloak:keycloak /opt/keycloak/docker-entrypoint.sh

# Drop privileges for runtime
USER keycloak

# Default Keycloak internal DB configuration (can be overridden at runtime)
ENV KC_DB=postgres
ENV KC_DB_URL=jdbc:postgresql://keycloak-postgres:5432/keycloak
ENV KC_DB_USERNAME=keycloak
ENV KC_DB_PASSWORD=keycloak_changeme

# OBP API configuration — override all of these at runtime
ENV OBP_API_URL=http://localhost:8080
ENV OBP_API_USERNAME=
ENV OBP_API_PASSWORD=
ENV OBP_API_CONSUMER_KEY=

# Default Keycloak runtime configuration (development-friendly)
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
ENV KC_HTTP_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange

# Custom "Forgot Password?" link URL (overrides Keycloak's default reset credentials page)
# Set at runtime to redirect users to an external password reset page.
# Leave unset to use Keycloak's built-in password reset flow.
# Example: FORGOT_PASSWORD_URL=https://portal.example.com/reset-password
ENV FORGOT_PASSWORD_URL=

# Start Keycloak in development mode by default (matches prior development Dockerfiles).
ENTRYPOINT ["/opt/keycloak/docker-entrypoint.sh", "start-dev", "--verbose"]
