package io.tesobe.providers;

import io.tesobe.config.DatabaseConfig;
import org.jboss.logging.Logger;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.provider.ProviderConfigurationBuilder;
import org.keycloak.storage.UserStorageProviderFactory;

import java.util.List;

public class KcUserStorageProviderFactory implements UserStorageProviderFactory<KcUserStorageProvider> {

    public static final String PROVIDER_ID = "obp-keycloak-provider";

    private static final Logger log = Logger.getLogger( KcUserStorageProviderFactory.class );
    private static volatile boolean configurationValidated = false;

    @Override
    public KcUserStorageProvider create(KeycloakSession session, ComponentModel model) {
        // Validate configuration on first provider creation
        if (!configurationValidated) {
            synchronized (this) {
                if (!configurationValidated) {
                    log.info("Validating runtime database configuration for OBP Keycloak Provider");
                    DatabaseConfig.validateConfiguration();
                    configurationValidated = true;
                }
            }
        }

        return new KcUserStorageProvider(session, model);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "OBP Keycloak PostgreSQL User Storage Provider - Runtime configurable via environment variables. Supports user lookup, authentication, registration, and profile updates.";
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
                .helpText("Set to true to enable this user storage provider")
                .add()
                .property()
                .name("cachePolicy")
                .type(ProviderConfigProperty.STRING_TYPE)
                .label("Cache Policy")
                .defaultValue("DEFAULT")
                .helpText("Cache policy for this provider")
                .add()
                .property()
                .name("importEnabled")
                .type(ProviderConfigProperty.BOOLEAN_TYPE)
                .label("Import Users")
                .defaultValue("true")
                .helpText("Enable importing users from external storage to Keycloak database")
                .add()
                .property()
                .name("syncRegistrations")
                .type(ProviderConfigProperty.BOOLEAN_TYPE)
                .label("Sync Registrations")
                .defaultValue("true")
                .helpText("Should newly created users be created in this external storage")
                .add()
                .property()
                .name("allowUserProfileEdit")
                .type(ProviderConfigProperty.BOOLEAN_TYPE)
                .label("Allow User Profile Editing")
                .defaultValue("true")
                .helpText("Allow users to edit their own profile information")
                .add()
                .property()
                .name("editMode")
                .type(ProviderConfigProperty.LIST_TYPE)
                .label("Edit Mode")
                .options("READ_ONLY", "WRITABLE", "UNSYNCED")
                .defaultValue("WRITABLE")
                .helpText("Set to WRITABLE to allow user profile updates")
                .add()
                .build();
    }





    @Override
    public void close() {
        log.info("Closing OBP Keycloak Provider Factory");
        // No resources to shutdown with JDBC approach
    }
}
