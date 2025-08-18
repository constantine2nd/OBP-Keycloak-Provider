package io.tesobe.requiredactions;

import io.tesobe.model.UserAdapter;
import jakarta.ws.rs.core.Response;
import java.util.List;
import org.jboss.logging.Logger;
import org.keycloak.authentication.RequiredActionContext;
import org.keycloak.authentication.RequiredActionProvider;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.UserModel;
import org.keycloak.models.utils.FormMessage;

/**
 * Custom Required Action Provider for OBP User Storage
 * This handles profile updates for federated users and routes them through our UserAdapter
 */
public class UpdateProfileRequiredAction implements RequiredActionProvider {

    private static final Logger log = Logger.getLogger(
        UpdateProfileRequiredAction.class
    );

    public static final String PROVIDER_ID = "VERIFY_PROFILE";

    @Override
    public void evaluateTriggers(RequiredActionContext context) {
        // Check if profile update is needed
        UserModel user = context.getUser();

        if (user instanceof UserAdapter) {
            log.infof(
                "OBP Required Action: evaluateTriggers for user: %s",
                user.getUsername()
            );

            // Check if basic profile fields are missing or need verification
            if (isProfileIncomplete(user)) {
                log.infof(
                    "Profile incomplete for user: %s, adding required action",
                    user.getUsername()
                );
                context.getUser().addRequiredAction(PROVIDER_ID);
            }
        }
    }

    @Override
    public void requiredActionChallenge(RequiredActionContext context) {
        log.infof(
            "OBP Required Action: requiredActionChallenge for user: %s",
            context.getUser().getUsername()
        );

        // Display the profile update form
        Response challenge = context
            .form()
            .setAttribute("user", context.getUser())
            .createForm("login-update-profile.ftl");

        context.challenge(challenge);
    }

    @Override
    public void processAction(RequiredActionContext context) {
        UserModel user = context.getUser();
        log.infof(
            "OBP Required Action: processAction for user: %s",
            user.getUsername()
        );

        // Get form parameters
        String firstName = context
            .getHttpRequest()
            .getDecodedFormParameters()
            .getFirst("firstName");
        String lastName = context
            .getHttpRequest()
            .getDecodedFormParameters()
            .getFirst("lastName");
        String email = context
            .getHttpRequest()
            .getDecodedFormParameters()
            .getFirst("email");

        log.infof(
            "Processing profile update: firstName=%s, lastName=%s, email=%s",
            firstName,
            lastName,
            email
        );

        // Validate input
        if (firstName == null || firstName.trim().isEmpty()) {
            context.challenge(
                createErrorResponse(
                    context,
                    "error-missing-firstname",
                    "First name is required"
                )
            );
            return;
        }

        if (lastName == null || lastName.trim().isEmpty()) {
            context.challenge(
                createErrorResponse(
                    context,
                    "error-missing-lastname",
                    "Last name is required"
                )
            );
            return;
        }

        if (email == null || email.trim().isEmpty() || !isValidEmail(email)) {
            context.challenge(
                createErrorResponse(
                    context,
                    "error-invalid-email",
                    "Valid email is required"
                )
            );
            return;
        }

        try {
            // Update user profile through our UserAdapter if it's a federated user
            if (user instanceof UserAdapter) {
                UserAdapter adapter = (UserAdapter) user;
                log.infof("Updating OBP federated user profile");

                adapter.setFirstName(firstName.trim());
                adapter.setLastName(lastName.trim());
                adapter.setEmail(email.trim());

                log.infof(
                    "Profile updated successfully for user: %s",
                    user.getUsername()
                );
            } else {
                // For non-federated users, use standard Keycloak methods
                log.infof("Updating standard user profile");
                user.setFirstName(firstName.trim());
                user.setLastName(lastName.trim());
                user.setEmail(email.trim());
            }

            // Mark the required action as complete
            user.removeRequiredAction(PROVIDER_ID);
            context.success();

            log.infof(
                "Required action completed for user: %s",
                user.getUsername()
            );
        } catch (Exception e) {
            log.errorf(
                "Error updating profile for user %s: %s",
                user.getUsername(),
                e.getMessage()
            );
            context.challenge(
                createErrorResponse(
                    context,
                    "error-update-failed",
                    "Failed to update profile: " + e.getMessage()
                )
            );
        }
    }

    @Override
    public void close() {
        // No resources to close
    }

    /**
     * Check if user profile is incomplete
     */
    private boolean isProfileIncomplete(UserModel user) {
        return (
            user.getFirstName() == null ||
            user.getFirstName().trim().isEmpty() ||
            user.getLastName() == null ||
            user.getLastName().trim().isEmpty() ||
            user.getEmail() == null ||
            user.getEmail().trim().isEmpty()
        );
    }

    /**
     * Basic email validation
     */
    private boolean isValidEmail(String email) {
        return email != null && email.contains("@") && email.contains(".");
    }

    /**
     * Create error response with message
     */
    private Response createErrorResponse(
        RequiredActionContext context,
        String errorKey,
        String errorMessage
    ) {
        log.warnf("Profile update error: %s", errorMessage);

        return context
            .form()
            .setAttribute("user", context.getUser())
            .addError(new FormMessage(errorKey, errorMessage))
            .createForm("login-update-profile.ftl");
    }
}
