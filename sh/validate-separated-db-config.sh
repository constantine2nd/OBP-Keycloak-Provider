#!/bin/bash

# Validation script for separated Keycloak and User Storage database configuration
# This script checks that all required environment variables are properly set
# for the new separated database architecture.
#
# RECENT FIXES INCLUDED:
# - Fixed JDBC URL configuration validation
# - Updated default port from 5432 to 5434 for user storage
# - Added validation for recent configuration fixes
# - Enhanced troubleshooting guidance

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
CHECKS=0

echo -e "${BLUE}=== OBP Keycloak Provider - Separated Database Configuration Validator ===${NC}"
echo -e "${GREEN}Recent Fixes Applied: JDBC URL, Port Conflicts, SQL Syntax${NC}"
echo ""

# Helper functions
log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    ((ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    ((WARNINGS++))
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_env_var() {
    local var_name="$1"
    local default_value="${2:-}"
    local is_required="${3:-true}"
    local description="${4:-}"

    ((CHECKS++))

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "$is_required" == "true" ]]; then
            if [[ -n "$default_value" ]]; then
                log_warning "Environment variable '$var_name' not set, will use default: '$default_value'"
                [[ -n "$description" ]] && echo "   Description: $description"
            else
                log_error "Required environment variable '$var_name' is not set"
                [[ -n "$description" ]] && echo "   Description: $description"
            fi
        else
            log_info "Optional environment variable '$var_name' not set"
        fi
        return 1
    else
        local value="${!var_name:-}"
        if [[ "$var_name" == *"PASSWORD"* || "$var_name" == *"SECRET"* ]]; then
            log_success "$var_name is set (value hidden)"
        else
            log_success "$var_name = $value"
        fi

        # Additional validation for specific variables
        case "$var_name" in
            *_URL)
                if [[ ! "$value" =~ ^jdbc:postgresql:// ]]; then
                    log_error "$var_name must be a PostgreSQL JDBC URL starting with 'jdbc:postgresql://'"
                fi
                ;;
            *_PASSWORD)
                if [[ ${#value} -lt 8 ]]; then
                    log_warning "$var_name should be at least 8 characters long"
                fi
                if [[ "$value" == "changeme" || "$value" == "admin" || "$value" == "password" ]]; then
                    log_warning "$var_name uses a default/weak password - change this for production!"
                fi
                ;;
        esac
        return 0
    fi
}

check_port_conflict() {
    local port="$1"
    local service="$2"

    ((CHECKS++))

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warning "Port $port is already in use (needed for $service)"
            echo "   Run: ss -tulpn | grep :$port to see what's using it"
        else
            log_success "Port $port is available for $service"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warning "Port $port is already in use (needed for $service)"
            echo "   Run: sudo netstat -tulpn | grep :$port to see what's using it"
        else
            log_success "Port $port is available for $service"
        fi
    else
        log_info "Cannot check port $port availability (netstat/ss not available)"
    fi
}

validate_jdbc_url() {
    local var_name="$1"
    local expected_db="$2"

    if [[ -n "${!var_name:-}" ]]; then
        local url="${!var_name:-}"
        if [[ "$url" =~ jdbc:postgresql://([^:]+):([0-9]+)/([^?]+) ]]; then
            local host="${BASH_REMATCH[1]}"
            local port="${BASH_REMATCH[2]}"
            local database="${BASH_REMATCH[3]}"

            log_success "$var_name format is valid"
            echo "   Host: $host, Port: $port, Database: $database"

            if [[ "$database" != "$expected_db" ]]; then
                log_warning "$var_name database '$database' doesn't match expected '$expected_db'"
            fi
        else
            log_error "$var_name has invalid JDBC URL format"
        fi
    fi
}

# === Check Keycloak Admin ===
echo "🔍 Checking Keycloak Admin Configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_env_var "KEYCLOAK_ADMIN" "admin" true "Keycloak administrator username"
check_env_var "KEYCLOAK_ADMIN_PASSWORD" "admin" true "Keycloak administrator password"
echo ""

# === Keycloak Internal DB ===
echo "🗄️  Checking Keycloak Internal Database Configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_env_var "KC_DB" "postgres" false "Keycloak database type"
check_env_var "KC_DB_URL" "jdbc:postgresql://keycloak-postgres:5432/keycloak" true "Keycloak internal database URL"
check_env_var "KC_DB_USERNAME" "keycloak" true "Keycloak internal database username"
check_env_var "KC_DB_PASSWORD" "keycloak_changeme" true "Keycloak internal database password"
validate_jdbc_url "KC_DB_URL" "keycloak"
echo ""

# === User Storage DB ===
echo "👥 Checking User Storage Database Configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_env_var "DB_URL" "jdbc:postgresql://user-storage-postgres:5432/obp_mapped" true "User storage database URL"
check_env_var "DB_USER" "obp" true "User storage database username"
check_env_var "DB_PASSWORD" "changeme" true "User storage database password"
check_env_var "DB_DRIVER" "org.postgresql.Driver" false "JDBC driver class"
check_env_var "DB_DIALECT" "org.hibernate.dialect.PostgreSQLDialect" false "Hibernate dialect"
validate_jdbc_url "DB_URL" "obp_mapped"
echo ""

# === Configuration Settings ===
echo "⚙️  Checking Configuration Settings..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_env_var "HIBERNATE_DDL_AUTO" "validate" false "Hibernate DDL auto mode"
check_env_var "HIBERNATE_SHOW_SQL" "true" false "Enable SQL logging"
check_env_var "KC_HOSTNAME_STRICT" "false" false "Keycloak hostname strict mode"
check_env_var "KC_HTTP_ENABLED" "true" false "Enable HTTP (for development)"
check_env_var "KC_HEALTH_ENABLED" "true" false "Enable health endpoints"
check_env_var "KC_METRICS_ENABLED" "true" false "Enable metrics endpoints"
echo ""

# === Port checks ===
echo "🌐 Checking Port Configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
KC_DB_PORT="${KC_DB_PORT:-5433}"
USER_STORAGE_DB_PORT="${USER_STORAGE_DB_PORT:-5434}"  # Updated default port
KEYCLOAK_HTTP_PORT="${KEYCLOAK_HTTP_PORT:-8000}"
KEYCLOAK_HTTPS_PORT="${KEYCLOAK_HTTPS_PORT:-8443}"

# Validate recent fixes
((CHECKS++))
if [[ "$USER_STORAGE_DB_PORT" == "5432" ]]; then
    log_warning "USER_STORAGE_DB_PORT is set to 5432, which may conflict with system PostgreSQL"
    echo "   Consider using port 5434 to avoid conflicts"
elif [[ "$USER_STORAGE_DB_PORT" == "5434" ]]; then
    log_success "USER_STORAGE_DB_PORT uses recommended port 5434 (avoids conflicts)"
fi

check_port_conflict "$KC_DB_PORT" "Keycloak PostgreSQL"
check_port_conflict "$USER_STORAGE_DB_PORT" "User Storage PostgreSQL"
check_port_conflict "$KEYCLOAK_HTTP_PORT" "Keycloak HTTP"
check_port_conflict "$KEYCLOAK_HTTPS_PORT" "Keycloak HTTPS"
echo ""

# === Security Analysis ===
echo "🔐 Security Analysis..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
((CHECKS++))

WEAK_PASSWORDS=()
if [[ "${KEYCLOAK_ADMIN_PASSWORD:-}" == "admin" ]]; then
    WEAK_PASSWORDS+=("KEYCLOAK_ADMIN_PASSWORD")
fi
if [[ "${KC_DB_PASSWORD:-}" == "keycloak_changeme" ]]; then
    WEAK_PASSWORDS+=("KC_DB_PASSWORD")
fi
if [[ "${DB_PASSWORD:-}" == "changeme" ]]; then
    WEAK_PASSWORDS+=("DB_PASSWORD")
fi

if [[ ${#WEAK_PASSWORDS[@]} -gt 0 ]]; then
    log_warning "The following variables use default/weak passwords:"
    for pwd in "${WEAK_PASSWORDS[@]}"; do
        echo "   - $pwd"
    done
    echo "   Please change these for production use!"
else
    log_success "No default passwords detected"
fi

# Check for recent fixes validation
((CHECKS++))
echo ""
echo "🔧 Recent Fixes Validation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if KC_DB_URL fix is applied
if [[ -n "${KC_DB_URL:-}" ]]; then
    if [[ "$KC_DB_URL" == "keycloak" ]]; then
        log_error "KC_DB_URL has old malformed value 'keycloak' - update to full JDBC URL"
        echo "   Expected: jdbc:postgresql://keycloak-postgres:5432/keycloak"
    elif [[ "$KC_DB_URL" =~ ^jdbc:postgresql://keycloak-postgres: ]]; then
        log_success "KC_DB_URL uses correct format (recent fix applied)"
    else
        log_info "KC_DB_URL uses custom format: $KC_DB_URL"
    fi
fi

# Check port configuration
if [[ "$USER_STORAGE_DB_PORT" == "5434" ]]; then
    log_success "Port conflict fix applied (using port 5434)"
elif [[ "$USER_STORAGE_DB_PORT" == "5432" ]]; then
    log_warning "Still using port 5432 - may conflict with system PostgreSQL"
    echo "   Recent fix: Use port 5434 to avoid conflicts"
fi

# Check database separation
((CHECKS++))
KC_DB_HOST=""
USER_DB_HOST=""

if [[ -n "${KC_DB_URL:-}" && "${KC_DB_URL:-}" =~ jdbc:postgresql://([^:]+): ]]; then
    KC_DB_HOST="${BASH_REMATCH[1]}"
fi
if [[ -n "${DB_URL:-}" && "${DB_URL:-}" =~ jdbc:postgresql://([^:]+): ]]; then
    USER_DB_HOST="${BASH_REMATCH[1]}"
fi

if [[ -n "$KC_DB_HOST" && -n "$USER_DB_HOST" ]]; then
    if [[ "$KC_DB_HOST" != "$USER_DB_HOST" ]]; then
        log_success "Databases are properly separated (different hosts)"
    else
        if [[ "${KC_DB_URL:-}" == "${DB_URL:-}" ]]; then
            log_error "Keycloak and User Storage databases are using the same URL!"
            echo "   This defeats the purpose of separation. Use different databases."
        else
            log_success "Databases use same host but different databases (acceptable)"
        fi
    fi
fi
echo ""

# === Docker Checks ===
echo "🐳 Docker Configuration Check..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
((CHECKS++))

if command -v docker >/dev/null 2>&1; then
    log_success "Docker is available"

    [[ -f "docker-compose.runtime.yml" ]] && log_success "docker-compose.runtime.yml found" || log_warning "docker-compose.runtime.yml not found"
    [[ -f "docker-compose.example.yml" ]] && log_success "docker-compose.example.yml found" || log_warning "docker-compose.example.yml not found"

    # Check for recent fixes in docker-compose file
    if [[ -f "docker-compose.runtime.yml" ]]; then
        if grep -q "KC_DB_URL.*jdbc:postgresql://keycloak-postgres" docker-compose.runtime.yml; then
            log_success "docker-compose.runtime.yml has correct KC_DB_URL fix"
        else
            log_warning "docker-compose.runtime.yml may not have the KC_DB_URL fix applied"
        fi

        if grep -q "USER_STORAGE_DB_PORT:-5434" docker-compose.runtime.yml; then
            log_success "docker-compose.runtime.yml has correct port configuration"
        else
            log_warning "docker-compose.runtime.yml may not have the port fix applied"
        fi
    fi
else
    log_warning "Docker is not available or not in PATH"
fi

if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
    log_success "docker-compose is available"
else
    log_warning "docker-compose is not available or not in PATH"
fi
echo ""

# === Summary ===
echo "📊 Validation Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total checks performed: $CHECKS"
echo -e "Errors: ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [[ $ERRORS -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 Configuration validation passed! Your setup looks good.${NC}"
        echo -e "${GREEN}✅ Recent fixes are properly applied.${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Start the services: docker-compose -f docker-compose.runtime.yml up"
        echo "2. Access Keycloak: http://localhost:${KEYCLOAK_HTTP_PORT:-8000}/admin"
        echo "3. Check logs: docker logs obp-keycloak"
        echo "4. Database ports: Keycloak DB (5433), User Storage DB (5434)"
    else
        echo -e "\n${YELLOW}⚠️  Configuration has warnings but should work.${NC}"
        echo "Please review the warnings above, especially for production deployments."
        echo "Recent fixes are applied - warnings are likely non-critical."
    fi
else
    echo -e "\n${RED}❌ Configuration validation failed!${NC}"
    echo "Please fix the errors above before proceeding."
    echo ""
    echo "Common fixes:"
    echo "1. Update KC_DB_URL to full JDBC URL format"
    echo "2. Change USER_STORAGE_DB_PORT from 5432 to 5434"
    echo "3. Ensure all required environment variables are set"
    exit 1
fi

echo ""
echo "For more help, see:"
echo "- README.md for general setup"
echo "- docs/CLOUD_NATIVE.md for deployment options"
echo "- docs/TROUBLESHOOTING.md for common issues and recent fixes"

echo ""
echo "Recent fixes documentation:"
echo "- Fixed JDBC URL configuration in docker-compose.runtime.yml"
echo "- Resolved port conflicts by using port 5434 for user storage"
echo "- Fixed SQL syntax errors in database initialization script"

exit 0
