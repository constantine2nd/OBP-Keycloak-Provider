package io.tesobe.model;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.jboss.logging.Logger;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.*;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.adapter.AbstractUserAdapterFederatedStorage;

public class UserAdapter extends AbstractUserAdapterFederatedStorage {

    private static final Logger log = Logger.getLogger(UserAdapter.class);
    private final KcUserEntity entity;
    private final String keycloakId;

    public UserAdapter(
        KeycloakSession session,
        RealmModel realm,
        ComponentModel model,
        KcUserEntity entity
    ) {
        super(session, realm, model);
        this.entity = entity;
        log.info("UserAdapter created for: " + this.entity);

        // Use primary key id for external ID generation
        String externalId;
        if (entity.getId() != null) {
            externalId = String.valueOf(entity.getId());
            log.debugf(
                "User %s using id-based external ID: %s",
                entity.getUsername(),
                externalId
            );
        } else {
            // This should never happen in a properly configured database
            log.errorf(
                "Primary key id is null for user: %s",
                entity.getUsername()
            );
            throw new IllegalStateException(
                "Primary key id is null for user: " +
                entity.getUsername() +
                " - this indicates a database integrity issue"
            );
        }

        this.keycloakId = StorageId.keycloakId(model, externalId);
    }

    // Username
    @Override
    public String getUsername() {
        return entity.getUsername();
    }

    @Override
    public void setUsername(String username) {
        log.info(
            "DIRECT setUsername() called with: " +
            username +
            " for user: " +
            getUsername()
        );
        if (!java.util.Objects.equals(entity.getUsername(), username)) {
            entity.setUsername(username);
            markAsModified();
            log.info(
                "Username update marked as modified, attempting to persist..."
            );
            persistProfileChangesDirectly();
            log.info("Username update persistence completed");
            // Also update the federated storage to ensure Keycloak sees the change
            super.setSingleAttribute("username", username);
        }
        // Note: Username updates should be handled carefully in production
    }

    // Email
    @Override
    public String getEmail() {
        return entity.getEmail();
    }

    @Override
    public void setEmail(String email) {
        log.info(
            "🔵 DIRECT setEmail() called with: " +
            email +
            " for user: " +
            getUsername()
        );
        log.info("Previous email was: " + entity.getEmail());
        if (!java.util.Objects.equals(entity.getEmail(), email)) {
            entity.setEmail(email);
            markAsModified();
            log.info(
                "Email update marked as modified, attempting to persist..."
            );
            persistProfileChangesDirectly();
            log.info("Email update persistence completed");
            // Also update the federated storage to ensure Keycloak sees the change
            super.setSingleAttribute("email", email);
        }
    }

    // First name
    @Override
    public String getFirstName() {
        return entity.getFirstName();
    }

    @Override
    public void setFirstName(String firstName) {
        log.info(
            "DIRECT setFirstName() called with: " +
            firstName +
            " for user: " +
            getUsername()
        );
        log.info("Previous first name was: " + entity.getFirstName());
        if (!java.util.Objects.equals(entity.getFirstName(), firstName)) {
            entity.setFirstName(firstName);
            markAsModified();
            log.info(
                "First name update marked as modified, attempting to persist..."
            );
            persistProfileChangesDirectly();
            log.info("First name update persistence completed");
            // Also update the federated storage to ensure Keycloak sees the change
            super.setSingleAttribute("firstName", firstName);
        }
    }

    // Last name
    @Override
    public String getLastName() {
        return entity.getLastName();
    }

    @Override
    public void setLastName(String lastName) {
        log.info(
            "DIRECT setLastName() called with: " +
            lastName +
            " for user: " +
            getUsername()
        );
        log.info("Previous last name was: " + entity.getLastName());
        if (!java.util.Objects.equals(entity.getLastName(), lastName)) {
            entity.setLastName(lastName);
            markAsModified();
            log.info(
                "Last name update marked as modified, attempting to persist..."
            );
            persistProfileChangesDirectly();
            log.info("Last name update persistence completed");
            // Also update the federated storage to ensure Keycloak sees the change
            super.setSingleAttribute("lastName", lastName);
        }
    }

    // Password and salt (custom fields)
    public String getPassword() {
        return entity.getPassword();
    }

    public void setPassword(String password) {
        log.info("$ setPassword() called with: password = [" + password + "]");
        entity.setPassword(password);
    }

    public String getSalt() {
        return entity.getSalt();
    }

    public void setSalt(String salt) {
        log.info("$ setSalt() called with: " + salt);
        entity.setSalt(salt);
    }

    // Entity access for persistence operations
    public KcUserEntity getEntity() {
        return entity;
    }

    // Track modifications for persistence
    private boolean modified = false;

    private void markAsModified() {
        this.modified = true;
    }

    public boolean isModified() {
        return modified;
    }

    public void clearModified() {
        this.modified = false;
        log.infof("Modified flag cleared for user: %s", getUsername());
    }

    // Method to persist user profile changes directly to database
    public void persistProfileChangesDirectly() {
        log.warnf(
            "persistProfileChangesDirectly() called for user: %s, modified: %s - OPERATION DISABLED: authuser table is read-only",
            getUsername(),
            modified
        );

        if (modified) {
            log.warnf(
                "Profile changes requested for user: %s (ID: %d) - firstName='%s', lastName='%s', email='%s' - CHANGES NOT SAVED",
                getUsername(),
                entity.getId(),
                entity.getFirstName(),
                entity.getLastName(),
                entity.getEmail()
            );

            // The authuser table is read-only. Update operations are not supported.
            // This provider only supports reading existing users from the database.
            log.warnf(
                "Profile persistence blocked for user: %s - authuser table is read-only. " +
                "User profile changes must be made through other means outside of Keycloak.",
                getUsername()
            );

            // Clear the modified flag to prevent further attempts
            clearModified();
        } else {
            log.infof("No changes to persist for user: %s", getUsername());
        }
    }

    // Keycloak ID (used internally)
    @Override
    public String getId() {
        return keycloakId;
    }

    @Override
    public boolean isEmailVerified() {
        return Boolean.TRUE.equals(entity.getValidated());
    }

    @Override
    public void setEmailVerified(boolean verified) {
        log.infof(
            "setEmailVerified() called with: %s for user: %s",
            verified,
            getUsername()
        );
        entity.setValidated(verified);
    }

    // Optional: Required actions
    @Override
    public Stream<String> getRequiredActionsStream() {
        log.infof(
            "getRequiredActionsStream() called for user: %s",
            getUsername()
        );
        return super.getRequiredActionsStream(); // uses federated storage
    }

    // Additional profile update methods to catch all update mechanisms
    @Override
    public void removeAttribute(String name) {
        log.infof(
            "ATTRIBUTE removeAttribute() called: %s for user: %s",
            name,
            getUsername()
        );
        super.removeAttribute(name);
    }

    // Override core UserModel methods that might be called during updates
    @Override
    public boolean isEnabled() {
        return true; // Always enabled for federated users
    }

    @Override
    public void setEnabled(boolean enabled) {
        log.infof(
            "setEnabled() called with: %s for user: %s",
            enabled,
            getUsername()
        );
        // Store in entity if needed, or delegate to federated storage
        super.setEnabled(enabled);
    }

    // Override attribute management to handle profile updates
    @Override
    public void setSingleAttribute(String name, String value) {
        log.infof(
            "ATTRIBUTE setSingleAttribute() called: %s = %s for user: %s",
            name,
            value,
            getUsername()
        );

        // First update the federated storage
        super.setSingleAttribute(name, value);

        // Then update our entity and mark for persistence
        switch (name) {
            case "firstName":
                if (!java.util.Objects.equals(entity.getFirstName(), value)) {
                    log.info("Setting firstName via attribute: " + value);
                    entity.setFirstName(value);
                    markAsModified();
                    persistProfileChangesDirectly();
                }
                break;
            case "lastName":
                if (!java.util.Objects.equals(entity.getLastName(), value)) {
                    log.info("Setting lastName via attribute: " + value);
                    entity.setLastName(value);
                    markAsModified();
                    persistProfileChangesDirectly();
                }
                break;
            case "email":
                if (!java.util.Objects.equals(entity.getEmail(), value)) {
                    log.info("Setting email via attribute: " + value);
                    entity.setEmail(value);
                    markAsModified();
                    persistProfileChangesDirectly();
                }
                break;
            case "username":
                if (!java.util.Objects.equals(entity.getUsername(), value)) {
                    log.info("Setting username via attribute: " + value);
                    entity.setUsername(value);
                    markAsModified();
                    persistProfileChangesDirectly();
                }
                break;
            default:
                // For other attributes, just use federated storage
                break;
        }
    }

    @Override
    public void setAttribute(String name, List<String> values) {
        log.infof(
            "ATTRIBUTE setAttribute() called: %s = %s for user: %s",
            name,
            values,
            getUsername()
        );

        if (values == null || values.isEmpty()) {
            // Remove attribute case
            super.setAttribute(name, values);
            return;
        }

        // Use setSingleAttribute for core profile fields to ensure consistency
        String value = values.get(0);
        switch (name) {
            case "firstName":
            case "lastName":
            case "email":
            case "username":
                setSingleAttribute(name, value);
                break;
            default:
                super.setAttribute(name, values);
                break;
        }
    }

    @Override
    public String getFirstAttribute(String name) {
        switch (name) {
            case "firstName":
                return getFirstName();
            case "lastName":
                return getLastName();
            case "email":
                return getEmail();
            default:
                return super.getFirstAttribute(name);
        }
    }

    @Override
    public void addRequiredAction(String action) {
        log.infof(
            "addRequiredAction() called with: %s for user: %s",
            action,
            getUsername()
        );
        super.addRequiredAction(action);
    }

    @Override
    public void removeRequiredAction(String action) {
        log.infof(
            "removeRequiredAction() called with: %s for user: %s",
            action,
            getUsername()
        );
        super.removeRequiredAction(action);
    }

    // User attributes (handled by the methods above)

    @Override
    public Map<String, List<String>> getAttributes() {
        Map<String, List<String>> attributes = new HashMap<>(
            super.getAttributes()
        );

        // Ensure core profile attributes are available
        if (entity.getFirstName() != null) {
            attributes.put(
                "firstName",
                Collections.singletonList(entity.getFirstName())
            );
        }
        if (entity.getLastName() != null) {
            attributes.put(
                "lastName",
                Collections.singletonList(entity.getLastName())
            );
        }
        if (entity.getEmail() != null) {
            attributes.put(
                "email",
                Collections.singletonList(entity.getEmail())
            );
        }
        if (entity.getUsername() != null) {
            attributes.put(
                "username",
                Collections.singletonList(entity.getUsername())
            );
        }

        log.debugf(
            "getAttributes() called for user: %s, returning: %s",
            getUsername(),
            attributes.keySet()
        );
        return attributes;
    }

    // Optional: Groups
    @Override
    public Stream<GroupModel> getGroupsStream() {
        return super.getGroupsStream();
    }

    @Override
    public void joinGroup(GroupModel group) {
        super.joinGroup(group);
    }

    @Override
    public void leaveGroup(GroupModel group) {
        super.leaveGroup(group);
    }

    @Override
    public boolean isMemberOf(GroupModel group) {
        return super.isMemberOf(group);
    }

    // Optional: Roles
    @Override
    public Stream<RoleModel> getRoleMappingsStream() {
        return super.getRoleMappingsStream();
    }

    @Override
    public void grantRole(RoleModel role) {
        super.grantRole(role);
    }

    @Override
    public void deleteRoleMapping(RoleModel role) {
        super.deleteRoleMapping(role);
    }

    @Override
    public boolean hasRole(RoleModel role) {
        return super.hasRole(role);
    }

    @Override
    public Stream<RoleModel> getRealmRoleMappingsStream() {
        return super.getRealmRoleMappingsStream();
    }

    @Override
    public Stream<RoleModel> getClientRoleMappingsStream(ClientModel client) {
        return super.getClientRoleMappingsStream(client);
    }

    @Override
    public String toString() {
        return "UserAdapter[" + keycloakId + ", " + getUsername() + "]";
    }
}
