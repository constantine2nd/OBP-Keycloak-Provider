FROM maven:3-eclipse-temurin-17 as maven
COPY . /app
WORKDIR /app
RUN mvn clean install -DskipTests=true

FROM quay.io/keycloak/keycloak:latest as builder

# Enable Keycloak health and metrics endpoints
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange
ENV KC_DB=postgres

WORKDIR /opt/keycloak

# Prebuild the Keycloak server (e.g., compile extensions, optimize image)
ADD --chown=keycloak:keycloak https://jdbc.postgresql.org/download/postgresql-42.7.2.jar /opt/keycloak/providers/
COPY --from=maven /app/target/obp-keycloak-provider.jar /opt/keycloak/providers/
#RUN chown keycloak:keycloak /opt/keycloak/providers/obp-keycloak-provider.jar

RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:latest
COPY --from=builder /opt/keycloak/ /opt/keycloak/
RUN mkdir -p /opt/keycloak/themes/obp/login/resources/css/
COPY themes/styles.css /opt/keycloak/themes/obp/login/resources/css/
COPY themes/theme.properties /opt/keycloak/themes/obp/login/
USER keycloak
# Start Keycloak in development mode (enables features like auto-reload, less strict config)
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev", "--verbose"]
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
