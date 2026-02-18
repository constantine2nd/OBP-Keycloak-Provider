package io.tesobe.config;

import org.jboss.logging.Logger;

/**
 * Runtime configuration for OBP API access.
 *
 * Reads environment variables and provides them to OBPApiClient.
 * Follows the same singleton pattern as the removed DatabaseConfig.
 *
 * Required environment variables:
 *   OBP_API_URL          - Base URL of the OBP API (e.g. http://localhost:8080)
 *   OBP_API_USERNAME     - Admin user with CanGetAnyUser, CanVerifyUserCredentials, CanGetOidcClient roles
 *   OBP_API_PASSWORD     - Admin user password
 *   OBP_API_CONSUMER_KEY - Consumer key for Direct Login
 *   OBP_AUTHUSER_PROVIDER - Provider name used to filter users (security-critical)
 */
public class OBPApiConfig {

    private static final Logger log = Logger.getLogger(OBPApiConfig.class);
    private static volatile OBPApiConfig instance;
    private static final Object lock = new Object();

    private final String apiUrl;
    private final String apiUsername;
    private final String apiPassword;
    private final String apiConsumerKey;
    private final String authUserProvider;

    private OBPApiConfig() {
        this.apiUrl = getMandatoryEnv("OBP_API_URL");
        this.apiUsername = getMandatoryEnv("OBP_API_USERNAME");
        this.apiPassword = getMandatoryEnv("OBP_API_PASSWORD");
        this.apiConsumerKey = getMandatoryEnv("OBP_API_CONSUMER_KEY");
        this.authUserProvider = getMandatoryEnv("OBP_AUTHUSER_PROVIDER");

        log.infof("OBP API configuration loaded:");
        log.infof("  API URL: %s", this.apiUrl);
        log.infof("  API Username: %s", this.apiUsername);
        log.infof("  Auth User Provider: %s", this.authUserProvider);
    }

    public static OBPApiConfig getInstance() {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new OBPApiConfig();
                }
            }
        }
        return instance;
    }

    /**
     * Validates all required environment variables are present.
     * Throws RuntimeException with a clear message if any are missing.
     */
    public static void validateConfiguration() {
        StringBuilder missing = new StringBuilder();
        for (String var : new String[]{
            "OBP_API_URL", "OBP_API_USERNAME", "OBP_API_PASSWORD",
            "OBP_API_CONSUMER_KEY", "OBP_AUTHUSER_PROVIDER"
        }) {
            String value = System.getenv(var);
            if (value == null || value.trim().isEmpty()) {
                missing.append(var).append(" ");
            }
        }
        if (missing.length() > 0) {
            String error = "FATAL: Required environment variables not set: " +
                missing.toString().trim() +
                ". These variables are mandatory for OBP API authentication.";
            log.error(error);
            throw new RuntimeException(error);
        }
        log.info("All required OBP API environment variables are configured");
    }

    private static String getMandatoryEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.trim().isEmpty()) {
            String msg = "FATAL: Mandatory environment variable '" + name +
                "' is not set. Please configure it in your environment.";
            log.error(msg);
            throw new RuntimeException(msg);
        }
        log.infof("Environment variable %s loaded", name);
        return value.trim();
    }

    // Package-private for tests
    static void resetInstance() {
        synchronized (lock) {
            instance = null;
        }
    }

    public String getApiUrl() {
        return apiUrl;
    }

    public String getApiUsername() {
        return apiUsername;
    }

    public String getApiPassword() {
        return apiPassword;
    }

    public String getApiConsumerKey() {
        return apiConsumerKey;
    }

    public String getAuthUserProvider() {
        return authUserProvider;
    }
}
