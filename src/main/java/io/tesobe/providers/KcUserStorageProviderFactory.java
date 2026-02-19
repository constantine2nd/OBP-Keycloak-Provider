package io.tesobe.providers;

import io.tesobe.config.OBPApiConfig;
import java.util.List;
import org.jboss.logging.Logger;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.provider.ProviderConfigurationBuilder;
import org.keycloak.storage.UserStorageProviderFactory;

public class KcUserStorageProviderFactory
    implements UserStorageProviderFactory<KcUserStorageProvider> {

    public static final String PROVIDER_ID = "obp-keycloak-provider";

    private static final Logger log = Logger.getLogger(KcUserStorageProviderFactory.class);
    private static volatile boolean configurationValidated = false;
    private static volatile OBPApiClient apiClient;

    @Override
    public KcUserStorageProvider create(KeycloakSession session, ComponentModel model) {
        if (!configurationValidated) {
            synchronized (this) {
                if (!configurationValidated) {
                    log.info("Validating OBP API configuration for OBP Keycloak Provider");
                    OBPApiConfig.validateConfiguration();
                    apiClient = new OBPApiClient(OBPApiConfig.getInstance());
                    if (!apiClient.testConnection()) {
                        log.warn("OBP API connection test failed at startup — provider registered " +
                            "but authentication will fail until OBP API is reachable. " +
                            "Check OBP_API_URL, OBP_API_USERNAME, OBP_API_PASSWORD, OBP_API_CONSUMER_KEY");
                    }
                    configurationValidated = true;
                }
            }
        }
        return new KcUserStorageProvider(session, model, apiClient);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "OBP Keycloak Provider — authenticates users via OBP REST API endpoints " +
            "(Direct Login + verify-credentials). Configured via environment variables.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return ProviderConfigurationBuilder.create()
            .property()
            .name("priority")
            .type(ProviderConfigProperty.STRING_TYPE)
            .label("Priority")
            .defaultValue("0")
            .helpText("Priority of this provider when looking up users. Lower values have higher priority.")
            .add()
            .property()
            .name("enabled")
            .type(ProviderConfigProperty.BOOLEAN_TYPE)
            .label("Enabled")
            .defaultValue("true")
            .helpText("Set to true to enable this user storage provider.")
            .add()
            .build();
    }

    @Override
    public void close() {
        log.info("Closing OBP Keycloak Provider Factory");
    }
}
