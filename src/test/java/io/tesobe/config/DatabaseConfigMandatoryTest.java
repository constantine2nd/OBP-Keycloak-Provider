package io.tesobe.config;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import static org.junit.jupiter.api.Assertions.*;
import java.lang.reflect.Field;
import java.util.Map;

/**
 * Test class to validate that OBP_AUTHUSER_PROVIDER is mandatory
 * and system fails properly when it's not configured.
 */
public class DatabaseConfigMandatoryTest {

    private Map<String, String> originalEnv;

    @BeforeEach
    public void setUp() throws Exception {
        // Clear any existing DatabaseConfig instance to ensure fresh test
        clearDatabaseConfigInstance();

        // Store original environment for restoration
        originalEnv = System.getenv();
    }

    @AfterEach
    public void tearDown() throws Exception {
        // Clear DatabaseConfig instance after each test
        clearDatabaseConfigInstance();

        // Restore original environment
        restoreEnvironment();
    }

    @Test
    public void testMissingObpAuthUserProviderThrowsException() {
        // Remove OBP_AUTHUSER_PROVIDER from environment if it exists
        removeEnvironmentVariable("OBP_AUTHUSER_PROVIDER");

        // Ensure other required variables are set to avoid other failures
        setEnvironmentVariable("DB_URL", "jdbc:postgresql://localhost:5432/test");
        setEnvironmentVariable("DB_USER", "test");
        setEnvironmentVariable("DB_PASSWORD", "test");

        // Attempt to get DatabaseConfig instance should throw RuntimeException
        RuntimeException exception = assertThrows(RuntimeException.class, () -> {
            DatabaseConfig.getInstance();
        });

        // Verify the error message contains information about the missing variable
        String message = exception.getMessage();
        assertTrue(message.contains("OBP_AUTHUSER_PROVIDER"),
            "Error message should mention OBP_AUTHUSER_PROVIDER");
        assertTrue(message.contains("FATAL"),
            "Error message should indicate this is a fatal error");
        assertTrue(message.contains("mandatory"),
            "Error message should indicate the variable is mandatory");
    }

    @Test
    public void testEmptyObpAuthUserProviderThrowsException() {
        // Set OBP_AUTHUSER_PROVIDER to empty string
        setEnvironmentVariable("OBP_AUTHUSER_PROVIDER", "");

        // Ensure other required variables are set
        setEnvironmentVariable("DB_URL", "jdbc:postgresql://localhost:5432/test");
        setEnvironmentVariable("DB_USER", "test");
        setEnvironmentVariable("DB_PASSWORD", "test");

        // Should throw RuntimeException for empty value
        RuntimeException exception = assertThrows(RuntimeException.class, () -> {
            DatabaseConfig.getInstance();
        });

        assertTrue(exception.getMessage().contains("OBP_AUTHUSER_PROVIDER"));
    }

    @Test
    public void testWhitespaceOnlyObpAuthUserProviderThrowsException() {
        // Set OBP_AUTHUSER_PROVIDER to whitespace only
        setEnvironmentVariable("OBP_AUTHUSER_PROVIDER", "   ");

        // Ensure other required variables are set
        setEnvironmentVariable("DB_URL", "jdbc:postgresql://localhost:5432/test");
        setEnvironmentVariable("DB_USER", "test");
        setEnvironmentVariable("DB_PASSWORD", "test");

        // Should throw RuntimeException for whitespace-only value
        RuntimeException exception = assertThrows(RuntimeException.class, () -> {
            DatabaseConfig.getInstance();
        });

        assertTrue(exception.getMessage().contains("OBP_AUTHUSER_PROVIDER"));
    }

    @Test
    public void testValidObpAuthUserProviderSucceeds() {
        // Set all required environment variables including OBP_AUTHUSER_PROVIDER
        setEnvironmentVariable("OBP_AUTHUSER_PROVIDER", "test_provider");
        setEnvironmentVariable("DB_URL", "jdbc:postgresql://localhost:5432/test");
        setEnvironmentVariable("DB_USER", "test");
        setEnvironmentVariable("DB_PASSWORD", "test");

        // Should not throw exception and should return valid config
        assertDoesNotThrow(() -> {
            DatabaseConfig config = DatabaseConfig.getInstance();
            assertNotNull(config);
            assertEquals("test_provider", config.getAuthUserProvider());
        });
    }

    @Test
    public void testProviderValueIsTrimmed() {
        // Set OBP_AUTHUSER_PROVIDER with leading/trailing whitespace
        setEnvironmentVariable("OBP_AUTHUSER_PROVIDER", "  test_provider  ");
        setEnvironmentVariable("DB_URL", "jdbc:postgresql://localhost:5432/test");
        setEnvironmentVariable("DB_USER", "test");
        setEnvironmentVariable("DB_PASSWORD", "test");

        DatabaseConfig config = DatabaseConfig.getInstance();
        assertEquals("test_provider", config.getAuthUserProvider(),
            "Provider value should be trimmed of whitespace");
    }

    /**
     * Helper method to clear the DatabaseConfig singleton instance using reflection
     * This allows each test to start with a fresh instance
     */
    private void clearDatabaseConfigInstance() throws Exception {
        Field instanceField = DatabaseConfig.class.getDeclaredField("instance");
        instanceField.setAccessible(true);
        instanceField.set(null, null);
    }

    /**
     * Helper method to set environment variable for testing
     * Uses reflection to modify the environment map
     */
    @SuppressWarnings("unchecked")
    private void setEnvironmentVariable(String key, String value) {
        try {
            Map<String, String> env = System.getenv();
            Field field = env.getClass().getDeclaredField("m");
            field.setAccessible(true);
            ((Map<String, String>) field.get(env)).put(key, value);
        } catch (Exception e) {
            // Fallback: use system property
            System.setProperty(key, value);
        }
    }

    /**
     * Helper method to remove environment variable for testing
     */
    @SuppressWarnings("unchecked")
    private void removeEnvironmentVariable(String key) {
        try {
            Map<String, String> env = System.getenv();
            Field field = env.getClass().getDeclaredField("m");
            field.setAccessible(true);
            ((Map<String, String>) field.get(env)).remove(key);
        } catch (Exception e) {
            // Fallback: clear system property
            System.clearProperty(key);
        }
    }

    /**
     * Helper method to restore original environment
     */
    @SuppressWarnings("unchecked")
    private void restoreEnvironment() {
        try {
            Map<String, String> env = System.getenv();
            Field field = env.getClass().getDeclaredField("m");
            field.setAccessible(true);
            ((Map<String, String>) field.get(env)).clear();
            ((Map<String, String>) field.get(env)).putAll(originalEnv);
        } catch (Exception e) {
            // Best effort restoration
        }
    }
}
