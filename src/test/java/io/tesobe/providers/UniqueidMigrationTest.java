package io.tesobe.providers;

import io.tesobe.model.KcUserEntity;
import io.tesobe.model.UserAdapter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.storage.StorageId;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Test class to verify the uniqueid to primary key migration logic.
 * This ensures that users are properly migrated from uniqueid-based external IDs
 * to primary key id-based external IDs.
 */
class UniqueidMigrationTest {

    private KeycloakSession mockSession;
    private RealmModel mockRealm;
    private ComponentModel mockModel;

    @BeforeEach
    void setUp() {
        mockSession = mock(KeycloakSession.class);
        mockRealm = mock(RealmModel.class);
        mockModel = mock(ComponentModel.class);

        // Set up component model ID for StorageId generation
        when(mockModel.getId()).thenReturn("test-provider-id");
    }

    @Test
    @DisplayName("New user with only primary key ID should use id-based external ID")
    void testNewUserWithIdOnly() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(123L);
        entity.setUsername("newuser");
        entity.setUniqueId(null); // No uniqueid for new users

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String keycloakId = adapter.getId();
        assertNotNull(keycloakId);
        assertTrue(keycloakId.contains("123"), "Keycloak ID should contain the primary key ID");
        assertFalse(keycloakId.contains("UNIQUE"), "Keycloak ID should not contain uniqueid format");
    }

    @Test
    @DisplayName("Legacy user with both id and uniqueid should prefer id-based external ID")
    void testLegacyUserMigration() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(456L);
        entity.setUsername("legacyuser");
        entity.setUniqueId("LEGACY_UNIQUE_ID_456789012345678901"); // Legacy uniqueid

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String keycloakId = adapter.getId();
        assertNotNull(keycloakId);
        assertTrue(keycloakId.contains("456"), "Keycloak ID should contain the primary key ID");
        assertFalse(keycloakId.contains("LEGACY_UNIQUE_ID"), "Keycloak ID should not contain the uniqueid");

        // Verify the external ID was generated from the primary key
        String externalId = StorageId.externalId(keycloakId);
        assertEquals("456", externalId, "External ID should be the primary key as string");
    }

    @Test
    @DisplayName("User with null primary key should throw IllegalStateException")
    void testUserWithNullIdThrowsException() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(null);
        entity.setUsername("invaliduser");
        entity.setUniqueId("SOME_UNIQUE_ID_123456789012345678");

        // Act & Assert
        IllegalStateException exception = assertThrows(
            IllegalStateException.class,
            () -> new UserAdapter(mockSession, mockRealm, mockModel, entity)
        );

        assertTrue(
            exception.getMessage().contains("Primary key id is null"),
            "Exception message should mention null primary key"
        );
        assertTrue(
            exception.getMessage().contains("invaliduser"),
            "Exception message should include username"
        );
    }

    @Test
    @DisplayName("User with zero primary key should use id-based external ID")
    void testUserWithZeroId() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(0L);
        entity.setUsername("zerouser");
        entity.setUniqueId("ZERO_USER_UNIQUE_ID_123456789012");

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String keycloakId = adapter.getId();
        assertNotNull(keycloakId);
        assertTrue(keycloakId.contains("0"), "Keycloak ID should contain zero as primary key");

        String externalId = StorageId.externalId(keycloakId);
        assertEquals("0", externalId, "External ID should be '0' for zero primary key");
    }

    @Test
    @DisplayName("Multiple users should generate unique Keycloak IDs")
    void testMultipleUsersUniqueIds() {
        // Arrange
        KcUserEntity user1 = new KcUserEntity();
        user1.setId(100L);
        user1.setUsername("user1");

        KcUserEntity user2 = new KcUserEntity();
        user2.setId(200L);
        user2.setUsername("user2");

        KcUserEntity user3 = new KcUserEntity();
        user3.setId(300L);
        user3.setUsername("user3");
        user3.setUniqueId("USER3_LEGACY_ID_123456789012345");

        // Act
        UserAdapter adapter1 = new UserAdapter(mockSession, mockRealm, mockModel, user1);
        UserAdapter adapter2 = new UserAdapter(mockSession, mockRealm, mockModel, user2);
        UserAdapter adapter3 = new UserAdapter(mockSession, mockRealm, mockModel, user3);

        // Assert
        String id1 = adapter1.getId();
        String id2 = adapter2.getId();
        String id3 = adapter3.getId();

        assertNotEquals(id1, id2, "User 1 and 2 should have different Keycloak IDs");
        assertNotEquals(id1, id3, "User 1 and 3 should have different Keycloak IDs");
        assertNotEquals(id2, id3, "User 2 and 3 should have different Keycloak IDs");

        // Verify external IDs are based on primary keys
        assertEquals("100", StorageId.externalId(id1));
        assertEquals("200", StorageId.externalId(id2));
        assertEquals("300", StorageId.externalId(id3));
    }

    @Test
    @DisplayName("Keycloak ID format should be consistent with StorageId format")
    void testKeycloakIdFormat() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(999L);
        entity.setUsername("formattest");

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String keycloakId = adapter.getId();

        // Verify the format follows StorageId convention: f:{provider-id}:{external-id}
        assertTrue(keycloakId.startsWith("f:"), "Keycloak ID should start with 'f:'");
        assertTrue(keycloakId.contains("test-provider-id"), "Keycloak ID should contain provider ID");
        assertTrue(keycloakId.endsWith(":999"), "Keycloak ID should end with external ID");

        // Verify we can extract the external ID correctly
        String extractedExternalId = StorageId.externalId(keycloakId);
        assertEquals("999", extractedExternalId, "Extracted external ID should match primary key");
    }

    @Test
    @DisplayName("Entity with very large primary key ID should work correctly")
    void testLargePrimaryKeyId() {
        // Arrange
        Long largeId = Long.MAX_VALUE - 1;
        KcUserEntity entity = new KcUserEntity();
        entity.setId(largeId);
        entity.setUsername("largeuser");

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String keycloakId = adapter.getId();
        assertNotNull(keycloakId);

        String externalId = StorageId.externalId(keycloakId);
        assertEquals(largeId.toString(), externalId, "External ID should handle large primary keys");
    }

    @Test
    @DisplayName("Username should be preserved regardless of ID migration")
    void testUsernamePreservation() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(777L);
        entity.setUsername("preserved_username");
        entity.setUniqueId("OLD_UNIQUE_ID_123456789012345678");

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        assertEquals("preserved_username", adapter.getUsername(),
            "Username should be preserved during migration");

        // Verify the underlying entity is also preserved
        assertEquals(entity, adapter.getEntity(),
            "Entity reference should be preserved");
    }

    @Test
    @DisplayName("Migration should work with entity containing all fields")
    void testMigrationWithCompleteEntity() {
        // Arrange
        KcUserEntity entity = new KcUserEntity();
        entity.setId(555L);
        entity.setUsername("complete_user");
        entity.setFirstName("Complete");
        entity.setLastName("User");
        entity.setEmail("complete@example.com");
        entity.setUniqueId("COMPLETE_USER_UNIQUE_ID_12345678");
        entity.setValidated(true);

        // Act
        UserAdapter adapter = new UserAdapter(mockSession, mockRealm, mockModel, entity);

        // Assert
        String externalId = StorageId.externalId(adapter.getId());
        assertEquals("555", externalId, "Should use primary key for external ID");

        // Verify other fields are accessible
        assertEquals("Complete", adapter.getFirstName());
        assertEquals("User", adapter.getLastName());
        assertEquals("complete@example.com", adapter.getEmail());
        assertTrue(adapter.isEmailVerified());
    }
}
