# authuser Table Read-Only Policy

## Overview

The `authuser` table in the OBP Keycloak User Storage Provider has been configured as **READ-ONLY**. This means that all write operations (INSERT, UPDATE, DELETE) through Keycloak are disabled and not supported.

## Policy Details

### ✅ Supported Operations (Read-Only)

- **User Authentication**: Users can log in with existing credentials
- **User Profile Viewing**: User information can be displayed in Keycloak admin console and user account
- **Password Validation**: Existing passwords are validated for authentication
- **User Search**: Users can be searched and listed in Keycloak
- **User Count**: Total user count can be retrieved

### 🔴 Disabled Operations (Write Operations)

- **User Creation**: `addUser()` method throws `UnsupportedOperationException`
- **User Profile Updates**: `updateUserProfile()` method returns `false` and logs warning
- **User Deletion**: `removeUser()` method throws `UnsupportedOperationException`
- **Direct Profile Persistence**: `persistProfileChangesDirectly()` method is disabled


## Technical Implementation

### Java Code Changes

#### KcUserStorageProvider.java

```java
@Override
public UserModel addUser(RealmModel realm, String username) {
    throw new UnsupportedOperationException(
        "User creation is not supported. The authuser table is read-only. " +
        "Users must be created through other means outside of Keycloak."
    );
}

@Override
public boolean removeUser(RealmModel realm, UserModel user) {
    throw new UnsupportedOperationException(
        "User deletion is not supported. The authuser table is read-only. " +
        "Users must be removed through other means outside of Keycloak."
    );
}

public boolean updateUserProfile(UserModel user) {
    log.warnf(
        "updateUserProfile() called for user: %s - OPERATION DISABLED: authuser table is read-only",
        user.getUsername()
    );
    return false;
}
```

#### UserAdapter.java

```java
public void persistProfileChangesDirectly() {
    log.warnf(
        "persistProfileChangesDirectly() called for user: %s - OPERATION DISABLED: authuser table is read-only",
        getUsername()
    );
    // Changes are not persisted to database
}
```

### Expected Log Messages

When write operations are attempted, you will see these warning messages in the logs:

```
WARN: addUser() called with username: xyz - OPERATION DISABLED: authuser table is read-only
WARN: removeUser() called with persistenceId: xyz - OPERATION DISABLED: authuser table is read-only
WARN: updateUserProfile() called for user: xyz - OPERATION DISABLED: authuser table is read-only
WARN: persistProfileChangesDirectly() called for user: xyz - OPERATION DISABLED: authuser table is read-only
```

## User Management

### Adding New Users

Since Keycloak cannot create users, new users must be added directly to the `authuser` table using:

> **⚠️ CRITICAL**: The `authuser` table must be created and managed by a database administrator with appropriate CREATE and INSERT permissions on the `obp_mapped` database. Keycloak setup scripts cannot create this table due to read-only access restrictions.

1. **Direct SQL insertion by database administrator**:
   ```sql
   INSERT INTO public.authuser 
   (firstname, lastname, email, username, password_pw, password_slt, provider, locale, validated, user_c, createdat, updatedat, timezone, superuser)
   VALUES 
   ('John', 'Doe', 'john@example.com', 'johndoe', 'hashed_password', 'salt', 'provider_url', 'en_US', true, 1, NOW(), NOW(), 'UTC', false);
   ```

2. **External applications with database write access**
3. **Database administration tools (pgAdmin, psql, etc.)**
4. **Authorized database scripts run by administrators**

### Updating User Profiles

User profile updates must be performed outside of Keycloak by authorized administrators using:

1. **Direct SQL updates by database administrator**:
   ```sql
   UPDATE public.authuser 
   SET firstname = 'NewFirstName', lastname = 'NewLastName', email = 'newemail@example.com', updatedat = NOW() 
   WHERE username = 'johndoe';
   ```

2. **External applications with database write access**
3. **Database administration tools (pgAdmin, psql, etc.)**

### Removing Users

User deletion must be performed outside of Keycloak by authorized administrators using:

1. **Direct SQL deletion by database administrator**:
   ```sql
   DELETE FROM public.authuser WHERE username = 'johndoe';
   ```

2. **External applications with database write access**
3. **Database administration tools (pgAdmin, psql, etc.)**

## Impact on Existing Functionality

### Keycloak Admin Console

- User creation forms will result in errors
- User profile update attempts will appear to succeed but changes won't be saved
- User deletion attempts will result in errors
- User listing and viewing continues to work normally

### User Account Console

- Users can view their profiles normally
- Profile update attempts will appear to succeed but changes won't be saved
- Password changes are not affected (handled by Keycloak's credential management)

### Authentication Flow

- User login continues to work normally
- Password validation works as expected
- User sessions are managed by Keycloak as usual

## Script Changes

- `sh/run-local-postgres.sh`: Sample user INSERT removed
- `test-profile-update.sh`: Updated to expect blocked operations

## Documentation Updates

All documentation has been updated to reflect the read-only policy:

- `README.md`: Added read-only policy notice and limitations
- `docs/LOCAL_POSTGRESQL_SETUP.md`: Removed sample user insertion
- `docs/TROUBLESHOOTING.md`: Added read-only policy troubleshooting


## Benefits of Read-Only Policy

1. **Data Integrity**: Prevents accidental data corruption through Keycloak
2. **Security**: Reduces attack surface by eliminating write operations
3. **Separation of Concerns**: Clear separation between authentication and user management
4. **Audit Trail**: All user modifications must go through controlled external processes
5. **Compliance**: Easier to maintain compliance with data governance policies

## Troubleshooting

### Common Issues

1. **User Creation Fails**: Expected behavior. Use external tools to add users to the `authuser` table.

2. **Profile Updates Don't Save**: Expected behavior. Use external tools to update user profiles in the `authuser` table.

3. **User Deletion Fails**: Expected behavior. Use external tools to remove users from the `authuser` table.

### Verification Commands

Check if the policy is working correctly:

```bash
# Check Keycloak logs for read-only warnings
docker logs obp-keycloak-local 2>&1 | grep "OPERATION DISABLED"

# Verify table can be read
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -c "SELECT count(*) FROM authuser;"

# Test direct database operations (should work)
PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped -c "SELECT username, firstname, lastname FROM authuser LIMIT 5;"
```

## Reverting the Policy (If Needed)

If write operations need to be re-enabled in the future:

1. Restore the original implementation in `KcUserStorageProvider.java`
2. Restore the original implementation in `UserAdapter.java`
3. Update documentation to remove read-only notices
4. Re-enable sample user insertion in scripts
5. Update setup scripts to allow sample data insertion

**Note**: Reverting this policy should be done carefully and with proper testing to ensure data integrity.