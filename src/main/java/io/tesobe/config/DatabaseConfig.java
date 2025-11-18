package io.tesobe.config;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;
import org.jboss.logging.Logger;

/**
 * Runtime database configuration manager that reads environment variables
 * and provides JDBC connections for cloud-native deployments.
 *
 * This approach uses direct JDBC instead of JPA to avoid conflicts with
 * Keycloak's internal Quarkus/Hibernate configuration.
 */
public class DatabaseConfig {

    private static final Logger log = Logger.getLogger(DatabaseConfig.class);
    private static volatile DatabaseConfig instance;
    private static final Object lock = new Object();

    // Environment variable names
    private static final String DB_URL = "DB_URL";
    private static final String DB_USER = "DB_USER";
    private static final String DB_PASSWORD = "DB_PASSWORD";
    private static final String DB_DRIVER = "DB_DRIVER";
    private static final String DB_AUTHUSER_TABLE = "DB_AUTHUSER_TABLE";
    private static final String OBP_AUTHUSER_PROVIDER = "OBP_AUTHUSER_PROVIDER";

    // Default values
    private static final String DEFAULT_DB_URL =
        "jdbc:postgresql://localhost:5434/obp_mapped";
    private static final String DEFAULT_DB_USER = "obp";
    private static final String DEFAULT_DB_PASSWORD = "f";
    private static final String DEFAULT_DB_DRIVER = "org.postgresql.Driver";
    private static final String DEFAULT_AUTHUSER_TABLE = "v_oidc_users";
    // No default for provider - it's mandatory

    // Configuration properties
    private final String dbUrl;
    private final String dbUser;
    private final String dbPassword;
    private final String dbDriver;
    private final String authUserTable;
    private final String authUserProvider;

    private DatabaseConfig() {
        // Load configuration from environment variables
        this.dbUrl = getEnvOrDefault(DB_URL, DEFAULT_DB_URL);
        this.dbUser = getEnvOrDefault(DB_USER, DEFAULT_DB_USER);
        this.dbPassword = getEnvOrDefault(DB_PASSWORD, DEFAULT_DB_PASSWORD);
        this.dbDriver = getEnvOrDefault(DB_DRIVER, DEFAULT_DB_DRIVER);
        this.authUserTable = getEnvOrDefault(
            DB_AUTHUSER_TABLE,
            DEFAULT_AUTHUSER_TABLE
        );
        this.authUserProvider = getMandatoryEnv(OBP_AUTHUSER_PROVIDER);

        // Load JDBC driver
        try {
            Class.forName(this.dbDriver);
            log.infof("JDBC driver loaded successfully: %s", this.dbDriver);
        } catch (ClassNotFoundException e) {
            log.errorf("Failed to load JDBC driver: %s", this.dbDriver);
            throw new RuntimeException(
                "Failed to load JDBC driver: " + this.dbDriver,
                e
            );
        }

        // Log configuration (without password)
        log.infof("Database configuration loaded:");
        log.infof("  URL: %s", this.dbUrl);
        log.infof("  User: %s", this.dbUser);
        log.infof("  Driver: %s", this.dbDriver);
        log.infof("  Auth User Table: %s", this.authUserTable);
        log.infof("  Auth User Provider: %s", this.authUserProvider);

        // Enhanced debugging for DB_AUTHUSER_TABLE
        String envValue = System.getenv(DB_AUTHUSER_TABLE);
        if (envValue != null && !envValue.trim().isEmpty()) {
            log.infof(
                "DEBUGGING: System.getenv('%s') = '%s'",
                DB_AUTHUSER_TABLE,
                envValue
            );
            if (!envValue.equals(this.authUserTable)) {
                log.errorf(
                    "MISMATCH: Expected '%s' but got '%s'",
                    envValue,
                    this.authUserTable
                );
            }
        } else {
            log.warnf(
                "DEBUGGING: System.getenv('%s') returned null or empty",
                DB_AUTHUSER_TABLE
            );
        }

        // Log all environment variables containing 'DB_' for debugging
        log.infof("All DB_* environment variables:");
        System.getenv()
            .entrySet()
            .stream()
            .filter(entry -> entry.getKey().startsWith("DB_"))
            .forEach(entry ->
                log.infof("  %s = %s", entry.getKey(), entry.getValue())
            );
    }

    /**
     * Gets the singleton instance of DatabaseConfig
     */
    public static DatabaseConfig getInstance() {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new DatabaseConfig();
                }
            }
        }
        return instance;
    }

    /**
     * Creates a new database connection
     */
    public Connection getConnection() throws SQLException {
        try {
            Properties props = new Properties();
            props.setProperty("user", dbUser);
            props.setProperty("password", dbPassword);

            // Set connection properties for better performance and reliability
            props.setProperty("ApplicationName", "OBP-Keycloak-Provider");
            props.setProperty("connectTimeout", "10");
            props.setProperty("socketTimeout", "30");
            props.setProperty("loginTimeout", "10");

            Connection connection = DriverManager.getConnection(dbUrl, props);
            connection.setAutoCommit(false); // Use transactions

            log.debugf("Database connection created successfully");
            return connection;
        } catch (SQLException e) {
            log.errorf(
                "Failed to create database connection: %s",
                e.getMessage()
            );
            throw e;
        }
    }

    /**
     * Tests the database connection
     */
    public boolean testConnection() {
        try (Connection conn = getConnection()) {
            boolean isValid = conn.isValid(5); // 5 second timeout
            if (isValid) {
                log.info("Database connection test successful");
            } else {
                log.warn(
                    "Database connection test failed - connection not valid"
                );
            }
            return isValid;
        } catch (SQLException e) {
            log.errorf("Database connection test failed: %s", e.getMessage());
            return false;
        }
    }

    /**
     * Validates that all required environment variables are set
     */
    public static void validateConfiguration() {
        StringBuilder missingVars = new StringBuilder();

        if (isEnvMissing(DB_URL)) missingVars.append(DB_URL).append(" ");
        if (isEnvMissing(DB_USER)) missingVars.append(DB_USER).append(" ");
        if (isEnvMissing(DB_PASSWORD)) missingVars
            .append(DB_PASSWORD)
            .append(" ");
        if (isEnvMissing(OBP_AUTHUSER_PROVIDER)) missingVars
            .append(OBP_AUTHUSER_PROVIDER)
            .append(" ");

        if (missingVars.length() > 0) {
            String error =
                "FATAL: Required environment variables not set: " +
                missingVars.toString().trim() +
                ". These variables are mandatory for security and proper operation.";
            log.error(error);
            throw new RuntimeException(error);
        } else {
            log.info("All required environment variables are configured");
        }
    }

    /**
     * Gets environment variable value or returns default
     */
    private static String getEnvOrDefault(String envName, String defaultValue) {
        String value = System.getenv(envName);
        if (value == null || value.trim().isEmpty()) {
            log.warnf(
                "Environment variable %s not set, using default: %s",
                envName,
                defaultValue
            );
            return defaultValue;
        }
        log.infof(
            "Environment variable %s loaded: %s",
            envName,
            value.trim()
        );
        return value.trim();
    }

    /**
     * Gets mandatory environment variable value or throws exception
     */
    private static String getMandatoryEnv(String envName) {
        String value = System.getenv(envName);
        if (value == null || value.trim().isEmpty()) {
            String error = String.format(
                "FATAL: Mandatory environment variable '%s' is not set. " +
                "This variable is required for security and must be configured. " +
                "Please set %s=your_provider_name in your environment configuration.",
                envName,
                envName
            );
            log.error(error);
            throw new RuntimeException(error);
        }
        log.infof(
            "Mandatory environment variable %s loaded: %s",
            envName,
            value.trim()
        );
        return value.trim();
    }

    /**
     * Checks if environment variable is missing or empty
     */
    private static boolean isEnvMissing(String envName) {
        String value = System.getenv(envName);
        return value == null || value.trim().isEmpty();
    }

    /**
     * Gets current database configuration as a map (for debugging/monitoring)
     */
    public Map<String, String> getCurrentConfig() {
        Map<String, String> config = new HashMap<>();
        config.put("db.url", this.dbUrl);
        config.put("db.user", this.dbUser);
        config.put("db.driver", this.dbDriver);
        // Note: We don't include the password for security reasons
        return config;
    }

    // Getter methods for configuration values
    public String getDbUrl() {
        return dbUrl;
    }

    public String getDbUser() {
        return dbUser;
    }

    public String getDbPassword() {
        return dbPassword;
    }

    public String getDbDriver() {
        return dbDriver;
    }

    /**
     * Get the configured table/view name for user data
     * @return The table/view name (default: "authuser", can be "v_oidc_users" for view-based access)
     */
    public String getAuthUserTable() {
        return authUserTable;
    }

    /**
     * Get the configured provider value for filtering user data
     * @return The provider value to filter by, or null if not configured
     */
    public String getAuthUserProvider() {
        return authUserProvider;
    }
}
