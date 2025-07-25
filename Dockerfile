FROM maven:3-eclipse-temurin-17 as maven
COPY . /app
WORKDIR /app
RUN mvn clean install -DskipTests=true

FROM quay.io/keycloak/keycloak:26.0.5 as builder

# Enable Keycloak health and metrics endpoints
#ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

WORKDIR /opt/keycloak

# Generate a self-signed SSL certificate for development/testing purposes
USER root
RUN keytool -genkeypair -storepass password -storetype PKCS12 \
    -keyalg RSA -keysize 2048 -dname "CN=server" -alias server \
    -ext "SAN:c=DNS:localhost,IP:127.0.0.1" \
    -keystore conf/server.keystore

# Prebuild the Keycloak server (e.g., compile extensions, optimize image)
RUN /opt/keycloak/bin/kc.sh build

FROM maven
ADD --chown=keycloak:keycloak /app/target/obp-keycloak-provider.jar /opt/keycloak/providers/

FROM quay.io/keycloak/keycloak:26.0.5
ADD --chown=keycloak:keycloak https://jdbc.postgresql.org/download/postgresql-42.7.2.jar /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Start Keycloak in development mode (enables features like auto-reload, less strict config)
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev", "--verbose"]
