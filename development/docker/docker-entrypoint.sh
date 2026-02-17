#!/bin/bash
# Custom entrypoint wrapper for OBP Keycloak Provider
# Injects runtime environment variables into theme configuration before starting Keycloak.

# --- Forgot Password URL override ---
# If FORGOT_PASSWORD_URL is set, inject it into all theme.properties files
# so the "Forgot Password?" link points to a custom URL instead of Keycloak's default.
if [ -n "$FORGOT_PASSWORD_URL" ]; then
    echo "[OBP Entrypoint] Setting forgotPasswordUrl=$FORGOT_PASSWORD_URL in theme properties"
    for f in /opt/keycloak/themes/*/theme.properties /opt/keycloak/themes/*/login/theme.properties; do
        if [ -f "$f" ]; then
            sed -i "s|^forgotPasswordUrl=.*|forgotPasswordUrl=$FORGOT_PASSWORD_URL|" "$f"
        fi
    done
fi

# Delegate to Keycloak's entrypoint
exec /opt/keycloak/bin/kc.sh "$@"
