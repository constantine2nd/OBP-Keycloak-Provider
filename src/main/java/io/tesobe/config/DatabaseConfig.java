package io.tesobe.config;

import org.jboss.logging.Logger;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

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

    // Default values
    private static final String DEFAULT_DB_URL = "jdbc:postgresql://localhost:5432/obp_mapped";
    private static final String DEFAULT_DB_USER = "obp";
    private static final String DEFAULT_DB_PASSWORD = "changeme";
    private static final String DEFAULT_DB_DRIVER = "org.postgresql.Driver";

    // Configuration properties
    private final String dbUrl;
    private final String dbUser;
    private final String dbPassword;
    private final String dbDriver;

    private DatabaseConfig() {
        // Load configuration from environment variables
        this.dbUrl = getEnvOrDefault(DB_URL, DEFAULT_DB_URL);
        this.dbUser = getEnvOrDefault(DB_USER, DEFAULT_DB_USER);
        this.dbPassword = getEnvOrDefault(DB_PASSWORD, DEFAULT_DB_PASSWORD);
        this.dbDriver = getEnvOrDefault(DB_DRIVER, DEFAULT_DB_DRIVER);

        // Load JDBC driver
        try {
            Class.forName(this.dbDriver);
            log.infof("JDBC driver loaded successfully: %s", this.dbDriver);
        } catch (ClassNotFoundException e) {
            log.errorf("Failed to load JDBC driver: %s", this.dbDriver);
            throw new RuntimeException("Failed to load JDBC driver: " + this.dbDriver, e);
        }

        // Log configuration (without password)
        log.infof("Database configuration loaded:");
        log.infof("  URL: %s", this.dbUrl);
        log.infof("  User: %s", this.dbUser);
        log.infof("  Driver: %s", this.dbDriver);
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
            log.errorf("Failed to create database connection: %s", e.getMessage());
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
                log.warn("Database connection test failed - connection not valid");
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
        if (isEnvMissing(DB_PASSWORD)) missingVars.append(DB_PASSWORD).append(" ");

        if (missingVars.length() > 0) {
            String warning = "Warning: Required environment variables not set: " + missingVars.toString().trim() +
                           ". Using default values which may not work in production.";
            log.warn(warning);
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
            log.debugf("Environment variable %s not set, using default: %s", envName, defaultValue);
            return defaultValue;
        }
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
}
