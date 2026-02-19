package io.tesobe.providers;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.tesobe.config.OBPApiConfig;
import io.tesobe.model.KcUserEntity;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.jboss.logging.Logger;

/**
 * HTTP client for OBP API authentication and user management.
 *
 * Uses Direct Login for admin authentication, then delegates user lookup and
 * credential verification to OBP API endpoints:
 *
 *   POST /obp/v6.0.0/my/logins/direct
 *       — obtain admin token; response: {"token": "..."}
 *
 *   GET  /obp/v6.0.0/users/provider/{PROVIDER}/username/{USERNAME}
 *       — lookup user by provider + username (PROVIDER must be percent-encoded)
 *         response: {"user_id","email","provider_id","provider","username","entitlements",...}
 *
 *   GET  /obp/v6.0.0/users/{USER_ID}
 *       — lookup user by UUID
 *
 *   GET  /obp/v6.0.0/users
 *       — list users (for Keycloak sync)
 *
 *   POST /obp/v6.0.0/users/verify-credentials
 *       — verify user password; body: {"username","password"}
 *
 *   GET  /obp/v6.0.0/oidc/clients/{CLIENT_ID}
 *       — verify OIDC client
 *
 *   GET  /obp/v6.0.0/providers
 *       — list providers (optional)
 *
 * Required admin roles: CanGetAnyUser, CanVerifyUserCredentials, CanGetOidcClient
 * Optional roles: CanGetProviders
 *
 * InterruptedException handling: every catch block re-interrupts the thread via
 * Thread.currentThread().interrupt() so Keycloak's executor lifecycle is preserved.
 */
public class OBPApiClient {

    private static final Logger log = Logger.getLogger(OBPApiClient.class);
    private static final ObjectMapper mapper = new ObjectMapper();

    private final OBPApiConfig config;
    private final HttpClient httpClient;
    private volatile String adminToken;

    public OBPApiClient(OBPApiConfig config) {
        this.config = config;
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    }

    /**
     * Tests connectivity by obtaining an admin Direct Login token.
     */
    public boolean testConnection() {
        String token = fetchNewToken();
        if (token != null) {
            synchronized (this) {
                adminToken = token;
            }
            log.info("OBP API connection test successful");
            return true;
        }
        log.error("OBP API connection test failed — could not obtain admin Direct Login token");
        return false;
    }

    // -------------------------------------------------------------------------
    // User lookup
    // -------------------------------------------------------------------------

    /**
     * Looks up a user by provider + username.
     * GET /obp/v6.0.0/users/provider/{PROVIDER}/username/{USERNAME}
     *
     * The provider (e.g. "http://127.0.0.1:8080") is percent-encoded so that colons
     * and slashes are treated as data rather than URL structure. OBP's routing layer
     * decodes it before matching.
     *
     * Requires CanGetAnyUser role on the admin account.
     */
    public KcUserEntity getUserByUsername(String username) {
        log.infof("getUserByUsername() via OBP API: %s", username);
        String path = "/obp/v6.0.0/users/provider/" + encode(config.getAuthUserProvider())
            + "/username/" + username;
        log.infof("getUserByUsername() resolved path: %s", path);
        return getUserFromPath(path);
    }

    /**
     * Looks up a user by their OBP user_id (UUID).
     * Requires CanGetAnyUser role on the admin account.
     */
    public KcUserEntity getUserById(String userId) {
        log.infof("getUserById() via OBP API: %s", userId);
        return getUserFromPath("/obp/v6.0.0/users/user-id/" + encode(userId));
    }

    /**
     * Lists users filtered in-memory by OBP_AUTHUSER_PROVIDER.
     * Offset and limit are applied after provider filtering.
     * Requires CanGetAnyUser role on the admin account.
     */
    public List<KcUserEntity> listUsers(int offset, int limit) {
        List<KcUserEntity> result = new ArrayList<>();
        try {
            HttpResponse<String> resp = callWithRetry("GET", "/obp/v6.0.0/users", null);
            if (resp == null || resp.statusCode() != 200) {
                log.warnf("listUsers() returned HTTP %s", resp != null ? resp.statusCode() : "null");
                return result;
            }
            JsonNode json = mapper.readTree(resp.body());
            JsonNode users = json.path("users");
            if (!users.isArray()) return result;

            int idx = 0;
            int count = 0;
            for (JsonNode userNode : users) {
                KcUserEntity entity = parseUser(userNode);
                if (entity == null) continue;
                if (!config.getAuthUserProvider().equals(entity.getProvider())) continue;
                if (idx++ < offset) continue;
                if (limit > 0 && count >= limit) break;
                result.add(entity);
                count++;
            }
            log.infof("listUsers() returned %d users for provider '%s'",
                result.size(), config.getAuthUserProvider());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("listUsers() interrupted");
        } catch (Exception e) {
            log.error("Error listing users from OBP API", e);
        }
        return result;
    }

    // -------------------------------------------------------------------------
    // Credential verification
    // -------------------------------------------------------------------------

    /**
     * Verifies a user's credentials via POST /obp/v6.0.0/users/verify-credentials.
     * Returns the user entity if credentials are valid AND provider matches, null otherwise.
     * Requires CanVerifyUserCredentials role on the admin account.
     */
    public KcUserEntity verifyUserCredentials(String username, String password) {
        log.infof("verifyUserCredentials() via OBP API for user: %s", username);
        try {
            ObjectNode body = mapper.createObjectNode();
            body.put("username", username);
            body.put("password", password);
            body.put("provider", config.getAuthUserProvider());
            String bodyStr = mapper.writeValueAsString(body);

            HttpResponse<String> resp = callWithRetry(
                "POST", "/obp/v6.0.0/users/verify-credentials", bodyStr);

            if (resp == null) {
                log.error("verifyUserCredentials() got null response");
                return null;
            }
            if (resp.statusCode() != 200 && resp.statusCode() != 201) {
                log.warnf("Credential verification failed for user '%s': HTTP %d — %s",
                    username, resp.statusCode(), resp.body());
                return null;
            }

            KcUserEntity entity = parseUser(mapper.readTree(resp.body()));
            if (entity == null) return null;

            if (!config.getAuthUserProvider().equals(entity.getProvider())) {
                log.infof("User '%s' has provider '%s', expected '%s' — rejected",
                    username, entity.getProvider(), config.getAuthUserProvider());
                return null;
            }

            log.infof("Credential verification SUCCESSFUL for user: %s", username);
            return entity;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("verifyUserCredentials() interrupted for user: " + username);
            return null;
        } catch (Exception e) {
            log.errorf("Error verifying credentials for user '%s'", username, e);
            return null;
        }
    }

    // -------------------------------------------------------------------------
    // OIDC / Providers (optional)
    // -------------------------------------------------------------------------

    /**
     * Fetches OIDC client details. Requires CanGetOidcClient role.
     */
    public JsonNode getOidcClient(String clientId) {
        log.infof("getOidcClient() via OBP API: %s", clientId);
        try {
            HttpResponse<String> resp = callWithRetry(
                "GET", "/obp/v6.0.0/oidc/clients/" + encode(clientId), null);
            if (resp != null && resp.statusCode() == 200) {
                return mapper.readTree(resp.body());
            }
            log.warnf("getOidcClient('%s') returned HTTP %s",
                clientId, resp != null ? resp.statusCode() : "null");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("getOidcClient() interrupted for: " + clientId);
        } catch (Exception e) {
            log.error("Error getting OIDC client: " + clientId, e);
        }
        return null;
    }

    /**
     * Lists available providers. Requires CanGetProviders role (optional).
     */
    public List<String> getProviders() {
        List<String> result = new ArrayList<>();
        try {
            HttpResponse<String> resp = callWithRetry("GET", "/obp/v6.0.0/providers", null);
            if (resp == null || resp.statusCode() != 200) return result;
            JsonNode json = mapper.readTree(resp.body());
            JsonNode providers = json.path("providers");
            if (providers.isArray()) {
                for (JsonNode p : providers) {
                    String id = p.path("id").asText(null);
                    if (id != null && !id.isEmpty()) result.add(id);
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("getProviders() interrupted");
        } catch (Exception e) {
            log.error("Error getting providers from OBP API", e);
        }
        return result;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    private KcUserEntity getUserFromPath(String path) {
        try {
            HttpResponse<String> resp = callWithRetry("GET", path, null);
            if (resp == null || resp.statusCode() != 200) {
                log.infof("getUserFromPath('%s') returned HTTP %s — %s",
                    path,
                    resp != null ? resp.statusCode() : "null",
                    resp != null ? resp.body() : "");
                return null;
            }
            KcUserEntity entity = parseUser(mapper.readTree(resp.body()));
            if (entity == null) return null;

            if (!config.getAuthUserProvider().equals(entity.getProvider())) {
                log.infof("User at '%s' has provider '%s', expected '%s' — filtered out",
                    path, entity.getProvider(), config.getAuthUserProvider());
                return null;
            }
            return entity;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.errorf("getUserFromPath() interrupted — Keycloak's execution time limit was " +
                "reached before OBP API responded. " +
                "ACTION REQUIRED: In Keycloak Admin Console go to User Federation > " +
                "obp-keycloak-provider > Settings and increase 'Max Lifespan' to at least " +
                "30000 (30 seconds). Path: %s", path);
            return null;
        } catch (Exception e) {
            log.error("Error fetching user from OBP API path: " + path, e);
            return null;
        }
    }

    private HttpResponse<String> callWithRetry(String method, String path, String body)
            throws Exception {
        String token = getToken();
        if (token == null) {
            log.error("Cannot call OBP API — no admin token available");
            return null;
        }
        HttpResponse<String> resp = call(method, path, body, token);
        if (resp.statusCode() == 401) {
            log.info("Admin token rejected (401) — refreshing and retrying once");
            invalidateToken();
            token = getToken();
            if (token == null) return null;
            resp = call(method, path, body, token);
        }
        return resp;
    }

    private HttpResponse<String> call(String method, String path, String body, String token)
            throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
            .uri(buildUri(path))
            .header("Content-Type", "application/json")
            .header("DirectLogin", "token=" + token)
            .timeout(Duration.ofSeconds(30));

        if ("GET".equals(method)) {
            builder.GET();
        } else {
            builder.POST(HttpRequest.BodyPublishers.ofString(body != null ? body : "{}"));
        }

        return httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private synchronized String getToken() {
        if (adminToken == null) {
            adminToken = fetchNewToken();
        }
        return adminToken;
    }

    private synchronized void invalidateToken() {
        adminToken = null;
    }

    private String fetchNewToken() {
        try {
            String directLoginHeader = String.format(
                "DirectLogin username=\"%s\",password=\"%s\",consumer_key=\"%s\"",
                config.getApiUsername(), config.getApiPassword(), config.getApiConsumerKey()
            );
            HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(config.getApiUrl() + "/obp/v6.0.0/my/logins/direct"))
                .header("Content-Type", "application/json")
                .header("DirectLogin", directLoginHeader)
                .POST(HttpRequest.BodyPublishers.ofString("{}"))
                .timeout(Duration.ofSeconds(30))
                .build();

            HttpResponse<String> resp = httpClient.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() == 200 || resp.statusCode() == 201) {
                JsonNode json = mapper.readTree(resp.body());
                String token = json.path("token").asText("");
                if (!token.isEmpty()) {
                    log.info("Admin Direct Login token obtained successfully");
                    return token;
                }
            }
            log.errorf("Failed to obtain admin token: HTTP %d — %s",
                resp.statusCode(), resp.body());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("fetchNewToken() interrupted");
        } catch (Exception e) {
            log.error("Error obtaining admin Direct Login token", e);
        }
        return null;
    }

    /**
     * Parses an OBP user JSON object into a KcUserEntity.
     *
     * Expected fields (from GET users/provider/.../username/... and verify-credentials):
     *   user_id    — UUID
     *   email      — user email
     *   provider   — authentication provider URL (e.g. "http://127.0.0.1:8080")
     *   provider_id — internal provider-side user identifier (not used by Keycloak)
     *   username   — login username
     *   firstname  — optional first name
     *   lastname   — optional last name
     */
    private KcUserEntity parseUser(JsonNode json) {
        if (json == null || json.isMissingNode() || json.isNull()) return null;

        String userId = json.path("user_id").asText(null);
        if (userId == null || userId.isEmpty()) return null;

        KcUserEntity entity = new KcUserEntity();
        entity.setId(userId);
        entity.setUsername(json.path("username").asText(null));
        entity.setEmail(json.path("email").asText(null));
        entity.setProvider(json.path("provider").asText(null));
        entity.setFirstName(json.path("firstname").asText(null));
        entity.setLastName(json.path("lastname").asText(null));
        entity.setValidated(true);
        entity.setSuperuser(false);
        entity.setPasswordShouldBeChanged(false);

        log.debugf("parseUser() → id=%s username=%s provider=%s email=%s",
            entity.getId(), entity.getUsername(), entity.getProvider(), entity.getEmail());
        return entity;
    }

    /**
     * Constructs a URI from the API base URL and a path.
     *
     * Uses the 5-argument URI constructor so that special characters already present
     * in the path (e.g. percent-encoded provider segments like "http%3A%2F%2F...") are
     * passed through without double-encoding.
     */
    private URI buildUri(String path) {
        try {
            URI base = URI.create(config.getApiUrl());
            return new URI(base.getScheme(), base.getAuthority(), path, null, null);
        } catch (URISyntaxException e) {
            throw new RuntimeException("Failed to construct URI for path: " + path, e);
        }
    }

    private static String encode(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
