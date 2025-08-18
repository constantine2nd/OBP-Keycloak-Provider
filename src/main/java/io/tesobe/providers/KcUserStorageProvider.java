package io.tesobe.providers;

import io.tesobe.config.DatabaseConfig;
import io.tesobe.model.KcUserEntity;
import io.tesobe.model.UserAdapter;
import java.sql.*;
import java.util.*;
import java.util.stream.Stream;
import org.jboss.logging.Logger;
import org.keycloak.component.ComponentModel;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialInputUpdater;
import org.keycloak.credential.CredentialInputValidator;
import org.keycloak.models.*;
import org.keycloak.models.cache.CachedUserModel;
import org.keycloak.models.cache.OnUserCache;
import org.keycloak.models.credential.PasswordCredentialModel;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.*;
import org.mindrot.jbcrypt.BCrypt;

public class KcUserStorageProvider
    implements
        UserStorageProvider,
        UserLookupProvider,
        UserRegistrationProvider,
        UserQueryProvider,
        CredentialInputUpdater,
        CredentialInputValidator,
        OnUserCache {

    private static final Logger log = Logger.getLogger(
        KcUserStorageProvider.class
    );
    public static final String PASSWORD_CACHE_KEY =
        UserAdapter.class.getName() + ".password";
    public static final String SALT_CACHE_KEY =
        UserAdapter.class.getName() + ".salt";

    private final KeycloakSession session;
    private final ComponentModel model;
    private final DatabaseConfig dbConfig;

    public KcUserStorageProvider(
        KeycloakSession session,
        ComponentModel model
    ) {
        this.session = session;
        this.model = model;
        this.dbConfig = DatabaseConfig.getInstance();

        log.info(
            "OBP User Storage Provider initialized with runtime configuration"
        );

        // Test database connection on initialization
        if (!dbConfig.testConnection()) {
            log.error(
                "Failed to connect to database during provider initialization"
            );
            throw new RuntimeException("Unable to connect to database");
        }
    }

    // Lifecycle
    @Override
    public void close() {
        log.info("OBP User Storage Provider closed");
        // No resources to close with JDBC approach
    }

    @Override
    public void preRemove(RealmModel realm) {
        log.infof("Realm %s is being removed", realm.getName());
    }

    @Override
    public void preRemove(RealmModel realm, GroupModel group) {
        log.infof(
            "Group %s is being removed from realm %s",
            group.getName(),
            realm.getName()
        );
    }

    @Override
    public void preRemove(RealmModel realm, RoleModel role) {
        log.infof(
            "Role %s is being removed from realm %s",
            role.getName(),
            realm.getName()
        );
    }

    @Override
    public void onCache(
        RealmModel realm,
        CachedUserModel user,
        UserModel delegate
    ) {
        String password = ((UserAdapter) delegate).getPassword();
        String salt = ((UserAdapter) delegate).getSalt();
        if (password != null) {
            user.getCachedWith().put(PASSWORD_CACHE_KEY, password);
            user.getCachedWith().put(SALT_CACHE_KEY, salt);
        }

        // Check if user profile was modified and persist changes
        if (delegate instanceof UserAdapter) {
            UserAdapter adapter = (UserAdapter) delegate;
            log.infof(
                "onCache() called for user: %s, modified: %s",
                user.getUsername(),
                adapter.isModified()
            );

            // Only persist if explicitly marked as modified to avoid interfering with user sessions
            if (adapter.isModified()) {
                log.infof(
                    "User profile was modified, persisting changes for: %s",
                    user.getUsername()
                );
                try {
                    updateUserProfile(delegate);
                    adapter.clearModified();
                    log.infof(
                        "Successfully persisted profile changes for user: %s",
                        user.getUsername()
                    );
                } catch (Exception e) {
                    log.errorf(
                        "Error persisting profile changes for user %s: %s",
                        user.getUsername(),
                        e.getMessage()
                    );
                }
            } else {
                log.infof(
                    "No profile changes to persist for user: %s",
                    user.getUsername()
                );
            }
        }
    }

    // Lookup
    @Override
    public UserModel getUserById(RealmModel realm, String id) {
        try {
            String externalId = StorageId.externalId(id);
            log.infof(
                "getUserById() called with: %s (external: %s)",
                id,
                externalId
            );

            String sql = "SELECT * FROM authuser WHERE uniqueid = ?";
            try (
                Connection conn = dbConfig.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)
            ) {
                stmt.setString(1, externalId);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        KcUserEntity entity = mapResultSetToEntity(rs);
                        UserAdapter adapter = new UserAdapter(
                            session,
                            realm,
                            model,
                            entity
                        );
                        log.infof(
                            "Created UserAdapter for user: %s",
                            entity.getUsername()
                        );
                        return adapter;
                    }
                }
            }
            return null;
        } catch (SQLException e) {
            log.error("Error in getUserById", e);
            return null;
        } catch (IllegalArgumentException ex) {
            log.warn("Invalid ID format: " + id, ex);
            return null;
        }
    }

    @Override
    public UserModel getUserByUsername(RealmModel realm, String username) {
        log.infof("getUserByUsername() called with: %s", username);

        String sql = "SELECT * FROM authuser WHERE username = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, username);
            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    log.infof(
                        "Created UserAdapter for user: %s",
                        entity.getUsername()
                    );
                    return adapter;
                }
            }
        } catch (SQLException e) {
            log.error("Error in getUserByUsername", e);
        }
        return null;
    }

    @Override
    public UserModel getUserByEmail(RealmModel realm, String email) {
        log.infof("getUserByEmail() called with: %s", email);

        String sql = "SELECT * FROM authuser WHERE email = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, email);
            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    return new UserAdapter(session, realm, model, entity);
                }
            }
        } catch (SQLException e) {
            log.error("Error in getUserByEmail", e);
        }
        return null;
    }

    // Registration
    @Override
    public UserModel addUser(RealmModel realm, String username) {
        log.infof("addUser() called with username: %s", username);

        String sql =
            "INSERT INTO authuser (username, firstname, lastname, uniqueid, createdat) VALUES (?, ?, ?, ?, ?)";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(
                sql,
                Statement.RETURN_GENERATED_KEYS
            )
        ) {
            String uniqueId = UUID.randomUUID().toString();
            stmt.setString(1, username);
            stmt.setString(2, "New");
            stmt.setString(3, "User");
            stmt.setString(4, uniqueId);
            stmt.setTimestamp(5, new Timestamp(System.currentTimeMillis()));

            int affectedRows = stmt.executeUpdate();
            if (affectedRows > 0) {
                conn.commit();

                // Create entity object for return
                KcUserEntity entity = new KcUserEntity();
                entity.setUsername(username);
                entity.setFirstName("New");
                entity.setLastName("User");
                entity.setUniqueId(uniqueId);

                try (ResultSet generatedKeys = stmt.getGeneratedKeys()) {
                    if (generatedKeys.next()) {
                        entity.setId(generatedKeys.getLong(1));
                    }
                }

                return new UserAdapter(session, realm, model, entity);
            }
        } catch (SQLException e) {
            log.error("Error in addUser", e);
        }
        return null;
    }

    @Override
    public boolean removeUser(RealmModel realm, UserModel user) {
        String persistenceId = StorageId.externalId(user.getId());
        log.infof("removeUser() called with persistenceId: %s", persistenceId);

        String sql = "DELETE FROM authuser WHERE uniqueid = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, persistenceId);
            int affectedRows = stmt.executeUpdate();
            if (affectedRows > 0) {
                conn.commit();
                return true;
            }
        } catch (SQLException e) {
            log.error("Error in removeUser", e);
        }
        return false;
    }

    // Credential support
    @Override
    public boolean supportsCredentialType(String credentialType) {
        return PasswordCredentialModel.TYPE.equals(credentialType);
    }

    @Override
    public boolean isConfiguredFor(
        RealmModel realm,
        UserModel user,
        String credentialType
    ) {
        return (
            supportsCredentialType(credentialType) && getPassword(user) != null
        );
    }

    @Override
    public boolean isValid(
        RealmModel realm,
        UserModel user,
        CredentialInput input
    ) {
        log.infof(
            "Password validation started for user: %s, input type: %s",
            user.getUsername(),
            input.getClass().getSimpleName()
        );

        // Check input type - accept both UserCredentialModel and PasswordCredentialModel
        if (!supportsCredentialType(input.getType())) {
            log.warnf(
                "Unsupported credential type: %s for user: %s",
                input.getType(),
                user.getUsername()
            );
            return false;
        }

        String storedHash = getPassword(user);
        String salt = getSalt(user);
        String rawPassword = input.getChallengeResponse();

        log.infof("Validating password for user: %s", user.getUsername());
        log.debugf(
            "Stored hash: %s",
            storedHash != null
                ? storedHash.substring(0, Math.min(10, storedHash.length())) +
                "..."
                : "null"
        );
        log.debugf(
            "Salt: %s",
            salt != null
                ? salt.substring(0, Math.min(8, salt.length())) + "..."
                : "null"
        );

        if (storedHash == null || salt == null) {
            log.warnf(
                "Missing stored password or salt for user: %s (hash: %s, salt: %s)",
                user.getUsername(),
                storedHash != null,
                salt != null
            );
            return false;
        }

        if (rawPassword == null || rawPassword.trim().isEmpty()) {
            log.warnf(
                "Empty or null password provided for user: %s",
                user.getUsername()
            );
            return false;
        }

        String fullBcryptHash;

        if (storedHash.startsWith("b;")) {
            // OBP format: "b;$2a$10$SGIAR0RtthMlgJK9DhElBekIvo5ulZ26GBZJQ" + salt
            // Reconstruct full BCrypt hash: $2a$10$SGIAR0RtthMlgJK9DhElBekIvo5ulZ26GBZJQnXiDOLye3CtjzEke
            String hashWithoutPrefix = storedHash.substring(2); // Remove "b;" prefix
            fullBcryptHash = hashWithoutPrefix + salt;
            log.infof(
                "Reconstructed BCrypt hash for user %s (length: %d)",
                user.getUsername(),
                fullBcryptHash.length()
            );
        } else {
            // Assume it's already a complete hash
            fullBcryptHash = storedHash;
            log.infof(
                "Using stored hash as-is for user %s (length: %d)",
                user.getUsername(),
                fullBcryptHash.length()
            );
        }

        // Validate BCrypt hash format
        if (!fullBcryptHash.matches("^\\$2[abyxy]?\\$\\d{2}\\$.{53}$")) {
            log.errorf(
                "Invalid BCrypt hash format for user %s: expected format $2a$rounds$salt+hash, got length %d",
                user.getUsername(),
                fullBcryptHash.length()
            );
            return false;
        }

        try {
            boolean isValid = BCrypt.checkpw(rawPassword, fullBcryptHash);
            if (isValid) {
                log.infof(
                    "Password validation SUCCESSFUL for user: %s",
                    user.getUsername()
                );
            } else {
                log.warnf(
                    "Password validation FAILED for user: %s",
                    user.getUsername()
                );
            }
            return isValid;
        } catch (IllegalArgumentException e) {
            log.errorf(
                "BCrypt validation error for user %s: %s",
                user.getUsername(),
                e.getMessage()
            );
            log.errorf("Full hash was: %s", fullBcryptHash);
            return false;
        } catch (Exception e) {
            log.errorf(
                "Unexpected error during password validation for user %s",
                user.getUsername(),
                e
            );
            return false;
        }
    }

    @Override
    public boolean updateCredential(
        RealmModel realm,
        UserModel user,
        CredentialInput input
    ) {
        if (!supportsCredentialType(input.getType())) {
            log.warnf(
                "Unsupported credential type for update: %s",
                input.getType()
            );
            return false;
        }

        String newPassword = input.getChallengeResponse();
        if (newPassword == null || newPassword.trim().isEmpty()) {
            log.warnf(
                "Empty password provided for credential update for user: %s",
                user.getUsername()
            );
            return false;
        }

        // Hash the new password using BCrypt
        String hashedPassword =
            "b;" + BCrypt.hashpw(newPassword, BCrypt.gensalt());
        getUserAdapter(user).setPassword(hashedPassword);
        log.infof("Password updated for user: %s", user.getUsername());
        return true;
    }

    @Override
    public void disableCredentialType(
        RealmModel realm,
        UserModel user,
        String credentialType
    ) {
        if (supportsCredentialType(credentialType)) {
            getUserAdapter(user).setPassword(null);
        }
    }

    @Override
    public Stream<String> getDisableableCredentialTypesStream(
        RealmModel realm,
        UserModel user
    ) {
        return getPassword(user) != null
            ? Stream.of(PasswordCredentialModel.TYPE)
            : Stream.empty();
    }

    private String getPassword(UserModel user) {
        if (user instanceof CachedUserModel) {
            return (String) ((CachedUserModel) user).getCachedWith().get(
                PASSWORD_CACHE_KEY
            );
        } else if (user instanceof UserAdapter) {
            return ((UserAdapter) user).getPassword();
        }
        return null;
    }

    private String getSalt(UserModel user) {
        if (user instanceof CachedUserModel) {
            return (String) ((CachedUserModel) user).getCachedWith().get(
                SALT_CACHE_KEY
            );
        } else if (user instanceof UserAdapter) {
            return ((UserAdapter) user).getSalt();
        }
        return null;
    }

    private UserAdapter getUserAdapter(UserModel user) {
        if (user instanceof CachedUserModel) {
            return (UserAdapter) ((CachedUserModel) user).getDelegateForUpdate();
        }
        return (UserAdapter) user;
    }

    // Queries
    @Override
    public int getUsersCount(RealmModel realm) {
        log.infof("getUsersCount() called for realm: %s", realm.getName());
        String sql = "SELECT COUNT(*) FROM authuser";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql);
            ResultSet rs = stmt.executeQuery()
        ) {
            if (rs.next()) {
                int count = rs.getInt(1);
                log.infof("Found %d users in database", count);
                return count;
            }
        } catch (SQLException e) {
            log.error("Error in getUsersCount", e);
        }
        return 0;
    }

    @Override
    public Stream<UserModel> searchForUserStream(
        RealmModel realm,
        String search,
        Integer first,
        Integer max
    ) {
        log.infof(
            "🔍 searchForUserStream() called: search='%s', first=%d, max=%d",
            search,
            first,
            max
        );
        List<UserModel> users = new ArrayList<>();

        String sql =
            "SELECT * FROM authuser WHERE LOWER(username) LIKE ? OR LOWER(email) LIKE ? OR LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ? ORDER BY username";

        // Add pagination if specified
        if (max != null && max >= 0) {
            sql += " LIMIT " + max;
        }
        if (first != null && first >= 0) {
            sql += " OFFSET " + first;
        }

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            String searchPattern = "%" + search.toLowerCase() + "%";
            stmt.setString(1, searchPattern);
            stmt.setString(2, searchPattern);
            stmt.setString(3, searchPattern);
            stmt.setString(4, searchPattern);

            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    users.add(new UserAdapter(session, realm, model, entity));
                }
            }
            log.infof(
                "🔍 Found %d users matching search '%s'",
                users.size(),
                search
            );
        } catch (SQLException e) {
            log.error("Error in searchForUserStream", e);
        }

        return users.stream();
    }

    @Override
    public Stream<UserModel> searchForUserStream(
        RealmModel realm,
        Map<String, String> params,
        Integer first,
        Integer max
    ) {
        log.infof("searchForUserStream() with params called: %s", params);

        // If no search params, return all users (for synchronization)
        if (params == null || params.isEmpty()) {
            return getAllUsers(realm, first, max);
        }

        // Handle specific parameter searches
        String username = params.get("username");
        String email = params.get("email");
        String search = params.get("search");

        if (username != null) {
            UserModel user = getUserByUsername(realm, username);
            return user != null ? Stream.of(user) : Stream.empty();
        }

        if (email != null) {
            UserModel user = getUserByEmail(realm, email);
            return user != null ? Stream.of(user) : Stream.empty();
        }

        if (search != null) {
            return searchForUserStream(realm, search, first, max);
        }

        return getAllUsers(realm, first, max);
    }

    @Override
    public Stream<UserModel> getGroupMembersStream(
        RealmModel realm,
        GroupModel group,
        Integer first,
        Integer max
    ) {
        return Stream.empty(); // Optional
    }

    @Override
    public Stream<UserModel> searchForUserByUserAttributeStream(
        RealmModel realm,
        String attr,
        String value
    ) {
        return Stream.empty(); // Optional
    }

    /**
     * Updates user profile information in the database
     */
    public boolean updateUserProfile(UserModel user) {
        if (!(user instanceof UserAdapter)) {
            log.warnf(
                "Cannot update profile for non-UserAdapter user: %s",
                user.getUsername()
            );
            return false;
        }

        UserAdapter adapter = (UserAdapter) user;
        KcUserEntity entity = adapter.getEntity();

        log.infof(
            "updateUserProfile() called for user: %s",
            user.getUsername()
        );
        log.infof(
            "Current values - firstName: '%s', lastName: '%s', email: '%s'",
            entity.getFirstName(),
            entity.getLastName(),
            entity.getEmail()
        );

        String sql =
            "UPDATE authuser SET firstname = ?, lastname = ?, email = ?, updatedat = ? WHERE id = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, entity.getFirstName());
            stmt.setString(2, entity.getLastName());
            stmt.setString(3, entity.getEmail());
            stmt.setTimestamp(4, new Timestamp(System.currentTimeMillis()));
            stmt.setLong(5, entity.getId());

            log.infof("Executing SQL: %s", sql);
            int affectedRows = stmt.executeUpdate();
            log.infof("SQL execution result: %d rows affected", affectedRows);

            if (affectedRows > 0) {
                conn.commit();
                log.infof(
                    "Successfully updated profile for user: %s",
                    user.getUsername()
                );
                return true;
            } else {
                log.warnf(
                    "No rows updated for user profile: %s",
                    user.getUsername()
                );
                return false;
            }
        } catch (SQLException e) {
            log.errorf(
                "Database error updating user profile for %s: %s",
                user.getUsername(),
                e.getMessage()
            );
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Maps a ResultSet row to a KcUserEntity object
     */
    private KcUserEntity mapResultSetToEntity(ResultSet rs)
        throws SQLException {
        KcUserEntity entity = new KcUserEntity();
        entity.setId(rs.getLong("id"));
        entity.setFirstName(rs.getString("firstname"));
        entity.setLastName(rs.getString("lastname"));
        entity.setEmail(rs.getString("email"));
        entity.setUsername(rs.getString("username"));
        entity.setPassword(rs.getString("password_pw"));
        entity.setSalt(rs.getString("password_slt"));
        entity.setProvider(rs.getString("provider"));
        entity.setLocale(rs.getString("locale"));
        entity.setValidated(rs.getBoolean("validated"));
        entity.setUserC(rs.getLong("user_c"));
        entity.setUniqueId(rs.getString("uniqueid"));
        Timestamp createdTs = rs.getTimestamp("createdat");
        Timestamp updatedTs = rs.getTimestamp("updatedat");
        entity.setCreatedAt(
            createdTs != null ? createdTs.toLocalDateTime() : null
        );
        entity.setUpdatedAt(
            updatedTs != null ? updatedTs.toLocalDateTime() : null
        );
        entity.setTimezone(rs.getString("timezone"));
        entity.setSuperuser(rs.getBoolean("superuser"));
        entity.setPasswordShouldBeChanged(
            rs.getBoolean("passwordshouldbechanged")
        );
        return entity;
    }

    /**
     * Get all users for synchronization
     */
    private Stream<UserModel> getAllUsers(
        RealmModel realm,
        Integer first,
        Integer max
    ) {
        log.infof(
            "getAllUsers() called for synchronization: first=%d, max=%d",
            first,
            max
        );
        List<UserModel> users = new ArrayList<>();

        String sql = "SELECT * FROM authuser ORDER BY username";

        // Add pagination if specified
        if (max != null && max >= 0) {
            sql += " LIMIT " + max;
        }
        if (first != null && first >= 0) {
            sql += " OFFSET " + first;
        }

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    users.add(adapter);
                }
            }
            log.infof("Retrieved %d users for synchronization", users.size());
        } catch (SQLException e) {
            log.errorf("❌ Error in getAllUsers: %s", e.getMessage());
        }

        return users.stream();
    }
}
