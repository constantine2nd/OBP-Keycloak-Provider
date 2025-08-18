package io.tesobe.model;

import java.time.LocalDateTime;

/**
 * User entity for OBP Keycloak Provider
 * Uses JDBC for database operations instead of JPA to avoid conflicts with Keycloak's internal configuration
 */
public class KcUserEntity {

    private Long id;
    private String firstName;
    private String lastName;
    private String email;
    private String username;
    private String password;
    private String salt;
    private String provider;
    private String locale;
    private Boolean validated;
    private Long userC;
    private String uniqueId;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private String timezone;
    private Boolean superuser;
    private Boolean passwordShouldBeChanged;

    // Getters and setters

    public Long getId() { return id; }

    public void setId(Long id) { this.id = id; }

    public String getFirstName() { return firstName; }

    public void setFirstName(String firstName) { this.firstName = firstName; }

    public String getLastName() { return lastName; }

    public void setLastName(String lastName) { this.lastName = lastName; }

    public String getEmail() { return email; }

    public void setEmail(String email) { this.email = email; }

    public String getUsername() { return username; }

    public void setUsername(String username) { this.username = username; }

    public String getPassword() { return password; }

    public void setPassword(String password) { this.password = password; }

    public String getSalt() { return salt; }

    public void setSalt(String salt) { this.salt = salt; }

    public String getProvider() { return provider; }

    public void setProvider(String provider) { this.provider = provider; }

    public String getLocale() { return locale; }

    public void setLocale(String locale) { this.locale = locale; }

    public Boolean getValidated() { return validated; }

    public void setValidated(Boolean validated) { this.validated = validated; }

    public Long getUserC() { return userC; }

    public void setUserC(Long userC) { this.userC = userC; }

    public String getUniqueId() { return uniqueId; }

    public void setUniqueId(String uniqueId) { this.uniqueId = uniqueId; }

    public LocalDateTime getCreatedAt() { return createdAt; }

    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }

    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }

    public String getTimezone() { return timezone; }

    public void setTimezone(String timezone) { this.timezone = timezone; }

    public Boolean getSuperuser() { return superuser; }

    public void setSuperuser(Boolean superuser) { this.superuser = superuser; }

    public Boolean getPasswordShouldBeChanged() { return passwordShouldBeChanged; }

    public void setPasswordShouldBeChanged(Boolean passwordShouldBeChanged) { this.passwordShouldBeChanged = passwordShouldBeChanged; }

    @Override
    public String toString() {
        return "KcUserEntity{" +
                "id=" + id +
                ", username='" + username + '\'' +
                ", email='" + email + '\'' +
                ", password='" + password + '\'' +
                ", salt='" + salt + '\'' +
                ", firstName='" + firstName + '\'' +
                ", lastName='" + lastName + '\'' +
                ", provider='" + provider + '\'' +
                ", locale='" + locale + '\'' +
                ", validated=" + validated +
                ", userC=" + userC +
                ", uniqueId='" + uniqueId + '\'' +
                ", createdAt=" + createdAt +
                ", updatedAt=" + updatedAt +
                ", timezone='" + timezone + '\'' +
                ", superuser=" + superuser +
                ", passwordShouldBeChanged=" + passwordShouldBeChanged +
                '}';
    }
}
