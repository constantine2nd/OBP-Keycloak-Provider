package io.tesobe.requiredactions;

import org.jboss.logging.Logger;
import org.keycloak.Config;
import org.keycloak.authentication.RequiredActionFactory;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

/**
 * Factory for OBP Update Profile Required Action Provider
 * This enables Keycloak to discover and use our custom required action
 */
public class UpdateProfileRequiredActionFactory
    implements RequiredActionFactory {

    private static final Logger log = Logger.getLogger(
        UpdateProfileRequiredActionFactory.class
    );

    public static final String PROVIDER_ID = "VERIFY_PROFILE";

    @Override
    public RequiredActionProvider create(KeycloakSession session) {
        log.debugf("Creating OBP Update Profile Required Action Provider");
        return new UpdateProfileRequiredAction();
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayText() {
        return "Verify Profile";
    }

    @Override
    public void init(Config.Scope config) {
        log.infof("Initializing OBP Update Profile Required Action Factory");
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
        log.infof("Post-init OBP Update Profile Required Action Factory");
    }

    @Override
    public void close() {
        log.infof("Closing OBP Update Profile Required Action Factory");
    }

    @Override
    public boolean isOneTimeAction() {
        // This action can be triggered multiple times if needed
        return false;
    }
}
