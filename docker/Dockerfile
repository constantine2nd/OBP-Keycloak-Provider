# === Build Stage ===
# Use official Keycloak image (26.0.5) as a base for building
FROM quay.io/keycloak/keycloak:26.0.5 as builder

# Build arguments for cache invalidation
ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# Enable Keycloak health and metrics endpoints
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Configure Keycloak to use PostgreSQL as its database
ENV KC_DB=postgres

# Set working directory inside the container
WORKDIR /opt/keycloak

# Switch to root user to perform privileged operations (e.g., keystore generation)
USER root

# Generate a self-signed SSL certificate for development/testing purposes
RUN keytool -genkeypair -storepass password -storetype PKCS12 \
    -keyalg RSA -keysize 2048 -dname "CN=server" -alias server \
    -ext "SAN:c=DNS:localhost,IP:127.0.0.1" \
    -keystore conf/server.keystore

# Add the PostgreSQL JDBC driver to the providers directory for database connectivity
ADD --chown=keycloak:keycloak https://jdbc.postgresql.org/download/postgresql-42.7.2.jar /opt/keycloak/providers/

# Cache invalidation layer - forces rebuild when JAR changes
RUN echo "Build timestamp: ${BUILD_TIMESTAMP}" > /tmp/build-info.txt && \
    echo "JAR checksum: ${JAR_CHECKSUM}" >> /tmp/build-info.txt

# Add your custom User Storage Provider (or other extensions) JAR
# This layer will be invalidated when the JAR changes due to the cache invalidation above
ADD --chown=keycloak:keycloak target/obp-keycloak-provider.jar /opt/keycloak/providers/

# Prebuild the Keycloak server (e.g., compile extensions, optimize image)
RUN /opt/keycloak/bin/kc.sh build


# === Final Runtime Image ===
# Use the same Keycloak base image for the final runtime image
FROM quay.io/keycloak/keycloak:26.0.5

# Copy the entire prebuilt Keycloak directory (including config, keystore) from the builder stage
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Copy build info for debugging
COPY --from=builder /tmp/build-info.txt /opt/keycloak/

# Set default Keycloak database configuration
# These will be overridden at runtime with proper values
ENV KC_DB=postgres
ENV KC_DB_URL=jdbc:postgresql://keycloak-postgres:5432/keycloak
ENV KC_DB_USERNAME=keycloak
ENV KC_DB_PASSWORD=keycloak_changeme

# Set default User Storage database configuration
# These are used by the OBP User Storage Provider
ENV DB_URL=jdbc:postgresql://user-storage-postgres:5432/obp_mapped
ENV DB_USER=obp
ENV DB_PASSWORD=changeme
ENV DB_DRIVER=org.postgresql.Driver
ENV DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect

# Default Hibernate configuration for User Storage
ENV HIBERNATE_DDL_AUTO=validate
ENV HIBERNATE_SHOW_SQL=true
ENV HIBERNATE_FORMAT_SQL=true

# Default Keycloak runtime configuration
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
ENV KC_HTTP_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange

# Start Keycloak in development mode (enables features like auto-reload, less strict config)
# Note: For production, use "start" instead of "start-dev"
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev", "--verbose"]
