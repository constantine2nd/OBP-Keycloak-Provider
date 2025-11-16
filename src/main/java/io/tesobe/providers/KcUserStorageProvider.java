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

        log.info("OBP User Storage Provider initialized successfully");
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

        // UserAdapter is read-only - no persistence operations needed
        if (delegate instanceof UserAdapter) {
            log.debugf(
                "onCache() called for read-only user: %s",
                user.getUsername()
            );
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

            // STEP 1: Try to find user by user_id (primary key) first - optimal path
            String sql =
                "SELECT " +
                getFieldList() +
                " FROM " +
                dbConfig.getAuthUserTable() +
                " WHERE user_id = ? AND provider = ?";
            try (
                Connection conn = dbConfig.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)
            ) {
                // Handle both numeric and string external IDs
                stmt.setString(1, externalId);
                stmt.setString(2, dbConfig.getAuthUserProvider());
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        KcUserEntity entity = mapResultSetToEntity(rs);
                        UserAdapter adapter = new UserAdapter(
                            session,
                            realm,
                            model,
                            entity
                        );
                        // Force refresh to ensure database is source of truth
                        adapter.forceRefreshFromDatabase();
                        log.infof(
                            "OPTIMAL: Found user %s by user_id %s with provider %s",
                            entity.getUsername(),
                            entity.getId(),
                            entity.getProvider()
                        );
                        return adapter;
                    }
                }
            }

            // User not found
            log.warnf("User not found with external ID: %s", externalId);
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

        String sql =
            "SELECT " +
            getFieldList() +
            " FROM " +
            dbConfig.getAuthUserTable() +
            " WHERE username = ? AND provider = ?";

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, username);
            stmt.setString(2, dbConfig.getAuthUserProvider());

            // Log the SQL query with actual parameter values for debugging
            String executableSql = sql
                .replaceFirst("\\?", "'" + username + "'")
                .replaceFirst("\\?", "'" + dbConfig.getAuthUserProvider() + "'");
            log.infof(
                "Executing SQL: %s",
                executableSql
            );
            log.infof(
                "Query parameters: [username='%s', provider='%s', table='%s']",
                username,
                dbConfig.getAuthUserProvider(),
                dbConfig.getAuthUserTable()
            );

            try (ResultSet rs = stmt.executeQuery()) {
                KcUserEntity entity = null;
                int rowCount = 0;

                while (rs.next()) {
                    rowCount++;
                    if (rowCount == 1) {
                        entity = mapResultSetToEntity(rs);
                    }
                }

                // Log the query result
                log.infof(
                    "Query result: found %d row(s) for username='%s' with provider='%s'",
                    rowCount,
                    username,
                    dbConfig.getAuthUserProvider()
                );

                if (rowCount > 1) {
                    log.errorf(
                        "Ambiguous login attempt: getUserByUsername found %d rows for username '%s' with provider '%s'. Login denied for security.",
                        rowCount,
                        username,
                        dbConfig.getAuthUserProvider()
                    );
                    return null;
                }

                if (entity != null) {
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    // Force refresh to ensure database is source of truth
                    adapter.forceRefreshFromDatabase();
                    log.infof(
                        "Created UserAdapter for user: %s with provider: %s",
                        entity.getUsername(),
                        entity.getProvider()
                    );
                    return adapter;
                }
            }
        } catch (SQLException e) {
            log.errorf(
                "SQL Error in getUserByUsername for username='%s', provider='%s', table='%s': %s",
                username,
                dbConfig.getAuthUserProvider(),
                dbConfig.getAuthUserTable(),
                e.getMessage()
            );
            log.error("Full SQL exception details:", e);
        }
        return null;
    }

    @Override
    public UserModel getUserByEmail(RealmModel realm, String email) {
        log.infof("getUserByEmail() called with: %s", email);

        String sql =
            "SELECT " +
            getFieldList() +
            " FROM " +
            dbConfig.getAuthUserTable() +
            " WHERE email = ? AND provider = ?";

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, email);
            stmt.setString(2, dbConfig.getAuthUserProvider());

            // Log the SQL query with actual parameter values for debugging
            String executableSql = sql
                .replaceFirst("\\?", "'" + email + "'")
                .replaceFirst("\\?", "'" + dbConfig.getAuthUserProvider() + "'");
            log.infof(
                "Executing SQL: %s",
                executableSql
            );
            log.infof(
                "Query parameters: [email='%s', provider='%s', table='%s']",
                email,
                dbConfig.getAuthUserProvider(),
                dbConfig.getAuthUserTable()
            );

            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    log.infof(
                        "Query result: found 1 row for email='%s' with provider='%s'",
                        email,
                        dbConfig.getAuthUserProvider()
                    );
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    log.infof(
                        "Created UserAdapter for email: %s with provider: %s",
                        entity.getEmail(),
                        entity.getProvider()
                    );
                    return adapter;
                } else {
                    log.infof(
                        "Query result: found 0 rows for email='%s' with provider='%s'",
                        email,
                        dbConfig.getAuthUserProvider()
                    );
                }
            }
        } catch (SQLException e) {
            log.errorf(
                "SQL Error in getUserByEmail for email='%s', provider='%s', table='%s': %s",
                email,
                dbConfig.getAuthUserProvider(),
                dbConfig.getAuthUserTable(),
                e.getMessage()
            );
            log.error("Full SQL exception details:", e);
        }
        return null;
    }

    // Registration
    @Override
    public UserModel addUser(RealmModel realm, String username) {
        log.warnf(
            "addUser() called with username: %s - OPERATION DISABLED: authuser table is read-only",
            username
        );

        // The authuser table is read-only. Write operations are not supported.
        // This provider only supports reading existing users from the database.
        throw new UnsupportedOperationException(
            "User creation is not supported. The authuser table is read-only. " +
                "Users must be created through other means outside of Keycloak."
        );
    }

    @Override
    public boolean removeUser(RealmModel realm, UserModel user) {
        String persistenceId = StorageId.externalId(user.getId());
        log.warnf(
            "removeUser() called with persistenceId: %s - OPERATION DISABLED: authuser table is read-only",
            persistenceId
        );

        // The authuser table is read-only. Delete operations are not supported.
        // This provider only supports reading existing users from the database.
        throw new UnsupportedOperationException(
            "User deletion is not supported. The authuser table is read-only. " +
                "Users must be removed through other means outside of Keycloak."
        );
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

        // Password updates are disabled - database is read-only
        log.warnf(
            "OPERATION DISABLED: Password update attempted for user %s. " +
                "Database is read-only. Use external tools to update passwords.",
            user.getUsername()
        );
        return false;
    }

    @Override
    public void disableCredentialType(
        RealmModel realm,
        UserModel user,
        String credentialType
    ) {
        log.warnf(
            "OPERATION DISABLED: Credential disable attempted for user %s, type %s. " +
                "Database is read-only. Use external tools to manage credentials.",
            user.getUsername(),
            credentialType
        );
        // Do nothing - database is source of truth
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
        String sql =
            "SELECT COUNT(*) FROM " +
            dbConfig.getAuthUserTable() +
            " WHERE provider = ?";

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            stmt.setString(1, dbConfig.getAuthUserProvider());

            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    int count = rs.getInt(1);
                    log.infof(
                        "Total users count for provider '%s': %d",
                        dbConfig.getAuthUserProvider(),
                        count
                    );
                    return count;
                }
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
            "searchForUserStream() called: search='%s', first=%d, max=%d",
            search,
            first,
            max
        );
        List<UserModel> users = new ArrayList<>();

        String sql =
            "SELECT " +
            getFieldList() +
            " FROM " +
            dbConfig.getAuthUserTable() +
            " WHERE (LOWER(username) LIKE ? OR LOWER(email) LIKE ? OR LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ?) AND provider = ? ORDER BY username";

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
            stmt.setString(5, dbConfig.getAuthUserProvider());

            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    // Force refresh to ensure database is source of truth
                    adapter.forceRefreshFromDatabase();
                    users.add(adapter);
                }
            }
            log.infof(
                "Found %d users matching search '%s'",
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
     * Gets the field list for SQL queries when using limited views
     * Only includes fields available in v_oidc_users1 and similar limited views
     */
    private String getFieldList() {
        return "user_id, username, firstname, lastname, email, validated, provider, password_pw, password_slt, createdat, updatedat";
    }

    /**
     * Maps a ResultSet row to a KcUserEntity object
     * Fields from v_oidc_users view (JOIN of authuser and resourceuser):
     * - user_id: UUID from resourceuser.userid_ (primary identifier)
     * - username, firstname, lastname, email, validated, provider: from authuser
     * - password_pw, password_slt: from authuser (for authentication)
     * - createdat, updatedat: timestamps from authuser
     */
    private KcUserEntity mapResultSetToEntity(ResultSet rs)
        throws SQLException {
        KcUserEntity entity = new KcUserEntity();
        entity.setId(rs.getString("user_id"));
        entity.setUsername(rs.getString("username"));
        entity.setFirstName(rs.getString("firstname"));
        entity.setLastName(rs.getString("lastname"));
        entity.setEmail(rs.getString("email"));
        entity.setValidated(rs.getBoolean("validated"));
        entity.setProvider(rs.getString("provider"));
        entity.setPassword(rs.getString("password_pw"));
        entity.setSalt(rs.getString("password_slt"));
        Timestamp createdTs = rs.getTimestamp("createdat");
        Timestamp updatedTs = rs.getTimestamp("updatedat");
        entity.setCreatedAt(
            createdTs != null ? createdTs.toLocalDateTime() : null
        );
        entity.setUpdatedAt(
            updatedTs != null ? updatedTs.toLocalDateTime() : null
        );

        // Fields not available in limited view - set to default values
        entity.setLocale(null);
        entity.setUserC(null);
        entity.setTimezone(null);
        entity.setSuperuser(false);
        entity.setPasswordShouldBeChanged(false);

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

        String sql =
            "SELECT " +
            getFieldList() +
            " FROM " +
            dbConfig.getAuthUserTable() +
            " WHERE provider = ? ORDER BY username";

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
            stmt.setString(1, dbConfig.getAuthUserProvider());
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    KcUserEntity entity = mapResultSetToEntity(rs);
                    UserAdapter adapter = new UserAdapter(
                        session,
                        realm,
                        model,
                        entity
                    );
                    // Force refresh to ensure database is source of truth
                    adapter.forceRefreshFromDatabase();
                    users.add(adapter);
                }
            }
            log.infof("Retrieved %d users for synchronization", users.size());
        } catch (SQLException e) {
            log.errorf("Error in getAllUsers: %s", e.getMessage());
        }

        return users.stream();
    }
}
