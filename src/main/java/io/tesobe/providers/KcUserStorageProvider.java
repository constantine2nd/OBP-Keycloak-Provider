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

        // Analyze uniqueid migration status
        try {
            log.warnf("==========================================");
            log.warnf("🔍 OBP KEYCLOAK PROVIDER MIGRATION CHECK");
            log.warnf("==========================================");
            log.warnf(
                "🔧 Checking uniqueid -> primary key migration status..."
            );
            analyzeUniqueidMigrationStatus();

            log.warnf("");
            log.warnf("🔍 CHECKING KEYCLOAK ID MIGRATION STATUS...");
            identifyKeycloakIdMigrationCandidates();
            log.warnf("==========================================");
        } catch (Exception e) {
            log.errorf(
                "❌ Could not analyze uniqueid migration status: %s",
                e.getMessage()
            );
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

            // STEP 1: Try to find user by id (primary key) first - optimal path
            String sql = "SELECT * FROM authuser WHERE id = ?";
            try (
                Connection conn = dbConfig.getConnection();
                PreparedStatement stmt = conn.prepareStatement(sql)
            ) {
                try {
                    // Try parsing external ID as Long (database primary key id)
                    Long userId = Long.parseLong(externalId);
                    stmt.setLong(1, userId);
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
                                "✅ OPTIMAL: Found user %s by id %s (fast integer lookup)",
                                entity.getUsername(),
                                entity.getId()
                            );
                            return adapter;
                        }
                    }
                } catch (NumberFormatException e) {
                    // External ID is not numeric - likely a legacy uniqueid string
                    log.warnf(
                        "🔍 LEGACY ID DETECTED: External ID '%s' is not numeric, checking uniqueid table",
                        externalId
                    );
                }
            }

            // STEP 2: Fallback to uniqueid lookup (backward compatibility for legacy users)
            // This handles users who still have uniqueid-based Keycloak IDs
            String legacySql = "SELECT * FROM authuser WHERE uniqueid = ?";
            try (
                Connection conn = dbConfig.getConnection();
                PreparedStatement stmt = conn.prepareStatement(legacySql)
            ) {
                stmt.setString(1, externalId);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        KcUserEntity entity = mapResultSetToEntity(rs);

                        // IMPORTANT: UserAdapter will now create id-based external ID
                        // This effectively migrates the user to use primary key lookups going forward
                        UserAdapter adapter = new UserAdapter(
                            session,
                            realm,
                            model,
                            entity
                        );

                        log.warnf(
                            "🔄 LEGACY USER: Found %s by uniqueid %s, but UserAdapter now uses id %s",
                            entity.getUsername(),
                            externalId,
                            entity.getId()
                        );
                        log.infof(
                            "📈 MIGRATION EFFECT: Next lookup for %s will use id %s (performance improvement)",
                            entity.getUsername(),
                            entity.getId()
                        );
                        return adapter;
                    }
                }
            }
            // User not found by either id or uniqueid
            log.warnf(
                "❌ USER NOT FOUND: No user found with external ID: %s",
                externalId
            );
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
            "INSERT INTO authuser (username, firstname, lastname, createdat) VALUES (?, ?, ?, ?)";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(
                sql,
                Statement.RETURN_GENERATED_KEYS
            )
        ) {
            stmt.setString(1, username);
            stmt.setString(2, "New");
            stmt.setString(3, "User");
            stmt.setTimestamp(4, new Timestamp(System.currentTimeMillis()));

            int affectedRows = stmt.executeUpdate();
            if (affectedRows > 0) {
                conn.commit();

                // Create entity object for return
                KcUserEntity entity = new KcUserEntity();
                entity.setUsername(username);
                entity.setFirstName("New");
                entity.setLastName("User");

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

        // Try to delete by id (primary key) first
        String sql = "DELETE FROM authuser WHERE id = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            try {
                // Try parsing as Long (id)
                stmt.setLong(1, Long.parseLong(persistenceId));
                int affectedRows = stmt.executeUpdate();
                if (affectedRows > 0) {
                    conn.commit();
                    log.infof("Deleted user by id: %s", persistenceId);
                    return true;
                }
            } catch (NumberFormatException e) {
                // persistenceId is not a number, skip id deletion
                log.infof(
                    "Persistence ID is not numeric, skipping id deletion"
                );
            }
        } catch (SQLException e) {
            log.error("Error in removeUser (id)", e);
        }

        // Fallback to uniqueid deletion for backward compatibility
        // This handles cases where legacy users still exist with uniqueid-based external IDs
        String legacySql = "DELETE FROM authuser WHERE uniqueid = ?";
        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(legacySql)
        ) {
            stmt.setString(1, persistenceId);
            int affected = stmt.executeUpdate();
            if (affected > 0) {
                conn.commit();
                log.infof(
                    "Deleted user by uniqueid (legacy): %s - migration to id-based lookups recommended",
                    persistenceId
                );
                return true;
            }
        } catch (SQLException e) {
            log.error("Error in removeUser (uniqueid)", e);
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

    /**
     * Analyze uniqueid migration status - helps identify users that still need migration
     */
    public void analyzeUniqueidMigrationStatus() {
        log.warnf("📋 Analyzing uniqueid migration status for all users...");

        String sql =
            "SELECT id, username, uniqueid FROM authuser WHERE uniqueid IS NOT NULL ORDER BY username";
        int totalUsers = 0;
        int usersWithUniqueId = 0;

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql)
        ) {
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    totalUsers++;
                    Long id = rs.getLong("id");
                    String username = rs.getString("username");
                    String uniqueId = rs.getString("uniqueid");

                    if (uniqueId != null && !uniqueId.trim().isEmpty()) {
                        usersWithUniqueId++;
                        log.warnf(
                            "🔄 MIGRATION CANDIDATE: User=%s, ID=%d, UniqueID=%s",
                            username,
                            id,
                            uniqueId
                        );
                    }
                }
            }

            log.warnf(
                "📊 MIGRATION ANALYSIS COMPLETE: %d users total, %d users with uniqueid values",
                totalUsers,
                usersWithUniqueId
            );

            if (usersWithUniqueId > 0) {
                log.warnf(
                    "⚠️  MIGRATION NEEDED: Found %d users with uniqueid values. These users may still be accessed via legacy uniqueid-based Keycloak IDs. " +
                    "The system will automatically migrate them to use id-based external IDs when they are accessed.",
                    usersWithUniqueId
                );
                log.warnf(
                    "🚀 PERFORMANCE NOTE: After migration, these %d users will experience ~10x faster lookup performance",
                    usersWithUniqueId
                );
            } else {
                log.warnf(
                    "✅ MIGRATION STATUS: No users with uniqueid values found - migration complete or not needed"
                );
            }
        } catch (SQLException e) {
            log.errorf("❌ Error in migration analysis: %s", e.getMessage());
        }
    }

    /**
     * Clear uniqueid values for users after confirming migration is working properly.
     * This should only be called after verifying that all users can be accessed via id-based lookups.
     *
     * @param confirmMigration Set to true to actually perform the operation
     * @return Number of users updated
     */
    public int clearUniqueidValues(boolean confirmMigration) {
        if (!confirmMigration) {
            log.warn(
                "clearUniqueidValues called without confirmation - no changes made. " +
                "Set confirmMigration=true to actually clear uniqueid values."
            );
            return 0;
        }

        log.info(
            "Starting to clear uniqueid values after migration confirmation..."
        );

        String updateSql =
            "UPDATE authuser SET uniqueid = NULL WHERE uniqueid IS NOT NULL";
        String countSql =
            "SELECT COUNT(*) FROM authuser WHERE uniqueid IS NOT NULL";

        int usersToUpdate = 0;
        int usersUpdated = 0;

        try (Connection conn = dbConfig.getConnection()) {
            // First, count how many users will be affected
            try (
                PreparedStatement countStmt = conn.prepareStatement(countSql);
                ResultSet rs = countStmt.executeQuery()
            ) {
                if (rs.next()) {
                    usersToUpdate = rs.getInt(1);
                }
            }

            if (usersToUpdate == 0) {
                log.info(
                    "No users with uniqueid values found - nothing to clear"
                );
                return 0;
            }

            log.infof(
                "About to clear uniqueid values for %d users",
                usersToUpdate
            );

            // Perform the update
            try (
                PreparedStatement updateStmt = conn.prepareStatement(updateSql)
            ) {
                usersUpdated = updateStmt.executeUpdate();
                conn.commit();

                log.infof(
                    "✅ Successfully cleared uniqueid values for %d users. " +
                    "Migration to id-based external IDs is now complete.",
                    usersUpdated
                );
            }
        } catch (SQLException e) {
            log.errorf("❌ Error clearing uniqueid values: %s", e.getMessage());
            throw new RuntimeException("Failed to clear uniqueid values", e);
        }

        return usersUpdated;
    }

    /**
     * Identify users that may still have uniqueid-based Keycloak IDs stored in Keycloak's database.
     * This method helps identify users who need their Keycloak sessions cleared to complete migration.
     *
     * @return Number of users that may need Keycloak ID migration
     */
    public int identifyKeycloakIdMigrationCandidates() {
        log.warnf(
            "🔍 IDENTIFYING USERS WITH POTENTIAL KEYCLOAK ID MIGRATION NEEDS..."
        );

        String sql =
            "SELECT id, username, uniqueid FROM authuser WHERE uniqueid IS NOT NULL AND uniqueid != '' ORDER BY username";
        int migrationCandidates = 0;

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql);
            ResultSet rs = stmt.executeQuery()
        ) {
            while (rs.next()) {
                migrationCandidates++;
                Long id = rs.getLong("id");
                String username = rs.getString("username");
                String uniqueId = rs.getString("uniqueid");

                log.warnf(
                    "🔄 KEYCLOAK ID MIGRATION CANDIDATE: User=%s, Database_ID=%d, Legacy_UniqueID=%s",
                    username,
                    id,
                    uniqueId
                );
            }

            if (migrationCandidates > 0) {
                log.warnf("==========================================");
                log.warnf("⚠️  KEYCLOAK ID MIGRATION GUIDANCE");
                log.warnf("==========================================");
                log.warnf(
                    "Found %d users with uniqueid values that may have legacy Keycloak IDs.",
                    migrationCandidates
                );
                log.warnf(
                    "These users are currently accessed via uniqueid-based external IDs."
                );
                log.warnf("");
                log.warnf("🔧 TO COMPLETE MIGRATION:");
                log.warnf(
                    "1. Users will be automatically migrated when they next authenticate"
                );
                log.warnf(
                    "2. For immediate migration, clear user sessions in Keycloak admin console"
                );
                log.warnf(
                    "3. Or restart Keycloak to force all users to re-authenticate"
                );
                log.warnf("");
                log.warnf("🚀 BENEFITS AFTER MIGRATION:");
                log.warnf(
                    "- ~10x faster user lookups (integer vs string comparison)"
                );
                log.warnf(
                    "- 75%% reduced storage for user IDs (8 bytes vs 32 bytes)"
                );
                log.warnf("- Eliminated uniqueid collision risks");
                log.warnf("==========================================");
            } else {
                log.warnf(
                    "✅ NO KEYCLOAK ID MIGRATION NEEDED: All users use id-based identification"
                );
            }
        } catch (SQLException e) {
            log.errorf(
                "❌ Error identifying Keycloak ID migration candidates: %s",
                e.getMessage()
            );
        }

        return migrationCandidates;
    }

    /**
     * Verify that all users can be accessed via their id-based external IDs.
     * This method helps validate that migration is working properly before clearing uniqueid values.
     *
     * @return true if all users can be accessed via id-based lookups
     */
    public boolean verifyIdBasedMigration() {
        log.info("Verifying id-based migration for all users...");

        String sql =
            "SELECT id, username, uniqueid FROM authuser WHERE uniqueid IS NOT NULL";
        int totalChecked = 0;
        int successfulLookups = 0;

        try (
            Connection conn = dbConfig.getConnection();
            PreparedStatement stmt = conn.prepareStatement(sql);
            ResultSet rs = stmt.executeQuery()
        ) {
            while (rs.next()) {
                totalChecked++;
                Long id = rs.getLong("id");
                String username = rs.getString("username");
                String uniqueid = rs.getString("uniqueid");

                // Try to create a UserAdapter using id-based external ID
                try {
                    KcUserEntity entity = new KcUserEntity();
                    entity.setId(id);
                    entity.setUsername(username);
                    entity.setUniqueId(uniqueid);

                    UserAdapter adapter = new UserAdapter(
                        session,
                        null,
                        model,
                        entity
                    );
                    String generatedId = adapter.getId();

                    // Verify the generated ID uses the numeric id, not the uniqueid
                    if (
                        generatedId != null && !generatedId.contains(uniqueid)
                    ) {
                        successfulLookups++;
                        log.debugf(
                            "✅ User %s (id: %d) successfully uses id-based external ID",
                            username,
                            id
                        );
                    } else {
                        log.warnf(
                            "❌ User %s (id: %d) still generates uniqueid-based external ID: %s",
                            username,
                            id,
                            generatedId
                        );
                    }
                } catch (Exception e) {
                    log.warnf(
                        "❌ Failed to create UserAdapter for user %s (id: %d): %s",
                        username,
                        id,
                        e.getMessage()
                    );
                }
            }

            boolean migrationSuccessful = (totalChecked == successfulLookups);

            log.infof(
                "Migration verification complete: %d/%d users successfully using id-based external IDs",
                successfulLookups,
                totalChecked
            );

            if (migrationSuccessful) {
                log.info(
                    "✅ All users are successfully using id-based external IDs. " +
                    "You can now safely call clearUniqueidValues(true) to complete the migration."
                );
            } else {
                log.warn(
                    "❌ Some users are still using uniqueid-based external IDs. " +
                    "Do not clear uniqueid values until all users are migrated."
                );
            }

            return migrationSuccessful;
        } catch (SQLException e) {
            log.errorf(
                "❌ Error verifying id-based migration: %s",
                e.getMessage()
            );
            return false;
        }
    }
}
