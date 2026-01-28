# Unified development Dockerfile for themed and standard builds
#
# Usage:
#  - Build a themed image:
#      docker build --build-arg KEYCLOAK_VERSION=26.5.1 --build-arg THEMED=true -t obp-keycloak:themed .
#  - Build a standard image (themes will be removed at the end):
#      docker build --build-arg KEYCLOAK_VERSION=26.5.1 --build-arg THEMED=false -t obp-keycloak:standard .
#
# Notes:
#  - This Dockerfile performs a Maven build inside the image (multi-stage). It mirrors the
#    pattern used by the previous themed Dockerfile to produce a self-contained image.
#  - Keycloak and JDBC driver versions are parameterized with build args.
#  - THEMED controls whether theme files are retained in the final image. The Docker build
#    context must contain the `themes/` directories (the repository includes them).
#
# Build arguments (defaults chosen to match development state):
ARG KEYCLOAK_VERSION=26.5.1
ARG POSTGRES_JDBC_URL=https://jdbc.postgresql.org/download/postgresql-42.7.2.jar
ARG MSSQL_JDBC_URL=https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.4.2.jre11/mssql-jdbc-12.4.2.jre11.jar
ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# === Build Stage: Maven ===
FROM maven:3-eclipse-temurin-17 AS maven

# Provide cache invalidation args (passed from CI/local scripts)
ARG BUILD_TIMESTAMP
ARG JAR_CHECKSUM

# Optional: application / database build-time parameters (kept for resource filtering if needed)
ARG DB_URL=jdbc:postgresql://localhost:5432/obp_mapped
ARG DB_USER=oidc_user
ARG DB_PASSWORD=your_secure_password
ARG DB_DRIVER=org.postgresql.Driver
ARG DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect

ARG KC_DB_URL=jdbc:postgresql://localhost:5433/keycloak
ARG KC_DB_USERNAME=keycloak
ARG KC_DB_PASSWORD=keycloak_changeme
ARG HIBERNATE_DDL_AUTO=validate
ARG HIBERNATE_SHOW_SQL=true
ARG HIBERNATE_FORMAT_SQL=true

# Copy project into build image and build the jar
COPY . /app
WORKDIR /app

# Cache invalidation marker
RUN echo "Build timestamp: ${BUILD_TIMESTAMP}" > /tmp/build-info.txt && \
    echo "JAR checksum: ${JAR_CHECKSUM}" >> /tmp/build-info.txt

# Build the project. Resource filtering can use the ARGs above.
RUN mvn clean install -DskipTests=true \
    -DDB_URL="${DB_URL}" \
    -DDB_USER="${DB_USER}" \
    -DDB_PASSWORD="${DB_PASSWORD}" \
    -DDB_DRIVER="${DB_DRIVER}" \
    -DDB_DIALECT="${DB_DIALECT}" \
    -DKC_DB_URL="${KC_DB_URL}" \
    -DKC_DB_USERNAME="${KC_DB_USERNAME}" \
    -DKC_DB_PASSWORD="${KC_DB_PASSWORD}" \
    -DHIBERNATE_DDL_AUTO="${HIBERNATE_DDL_AUTO}" \
    -DHIBERNATE_SHOW_SQL="${HIBERNATE_SHOW_SQL}" \
    -DHIBERNATE_FORMAT_SQL="${HIBERNATE_FORMAT_SQL}"

# === Keycloak Builder Stage ===
# Download JDBC drivers reliably in a small helper stage to avoid using remote ADD
FROM alpine:3.19 AS curler
RUN apk add --no-cache curl ca-certificates

# Re-declare the JDBC URL args for use in this stage
ARG POSTGRES_JDBC_URL
ARG MSSQL_JDBC_URL

# Fetch the JDBC driver artifacts into /tmp
RUN curl -fSL "${POSTGRES_JDBC_URL}" -o /tmp/postgresql.jar && \
    curl -fSL "${MSSQL_JDBC_URL}" -o /tmp/mssql.jar

FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} as builder

# Bring build args into this stage if needed for cache invalidation metadata
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

# Add JDBC drivers for Postgres and MSSQL to providers dir (copied from the curler stage)
COPY --from=curler --chown=keycloak:keycloak /tmp/postgresql.jar /opt/keycloak/providers/postgresql.jar
COPY --from=curler --chown=keycloak:keycloak /tmp/mssql.jar /opt/keycloak/providers/mssql.jar
# Also place stable-named copies into the Keycloak lib directory so the JDBC drivers are
# guaranteed to be on the application classpath (prevents ClassNotFound for driver classes)
COPY --from=curler --chown=keycloak:keycloak /tmp/postgresql.jar /opt/keycloak/lib/postgresql-42.7.2.jar
COPY --from=curler --chown=keycloak:keycloak /tmp/mssql.jar /opt/keycloak/lib/mssql-jdbc-12.4.2.jre11.jar

# Copy build metadata and the compiled provider jar from the maven stage
COPY --from=maven /tmp/build-info.txt /tmp/build-info.txt
COPY --from=maven /app/target/obp-keycloak-provider.jar /opt/keycloak/providers/

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

# Drop privileges for runtime
USER keycloak

# Default Keycloak DB and User Storage DB environment variables (can be overridden at runtime)
ENV KC_DB=postgres
ENV KC_DB_URL=jdbc:postgresql://keycloak-postgres:5432/keycloak
ENV KC_DB_USERNAME=keycloak
ENV KC_DB_PASSWORD=keycloak_changeme

ENV DB_URL=jdbc:postgresql://user-storage-postgres:5432/obp_mapped
ENV DB_USER=oidc_user
ENV DB_PASSWORD=your_secure_password
ENV DB_DRIVER=org.postgresql.Driver
ENV DB_DIALECT=org.hibernate.dialect.PostgreSQLDialect
ENV DB_AUTHUSER_TABLE=v_oidc_users

# Default Hibernate behavior
ENV HIBERNATE_DDL_AUTO=validate
ENV HIBERNATE_SHOW_SQL=true
ENV HIBERNATE_FORMAT_SQL=true

# Default Keycloak runtime configuration (development-friendly)
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
ENV KC_HTTP_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange

# Start Keycloak in development mode by default (matches prior development Dockerfiles).
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev", "--verbose"]
