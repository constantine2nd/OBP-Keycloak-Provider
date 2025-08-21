#!/bin/bash

# Test script for Local PostgreSQL Setup
# This script validates that the local PostgreSQL setup is working correctly
# with the OBP Keycloak Provider
#
# Usage: ./sh/test-local-postgres-setup.sh [OPTIONS]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Test configuration
KEYCLOAK_DB_NAME="keycloakdb"
KEYCLOAK_DB_USER="keycloak"
KEYCLOAK_DB_PASSWORD="f"
USER_STORAGE_DB_NAME="obp_mapped"
USER_STORAGE_DB_USER="obp"
USER_STORAGE_DB_PASSWORD="f"
CONTAINER_NAME="obp-keycloak-local"

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quick, -q      Quick test (basic connectivity only)"
    echo "  --full, -f       Full test suite (default)"
    echo "  --setup, -s      Include database setup verification"
    echo "  --container, -c  Test running container"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0               # Run full test suite"
    echo "  $0 --quick       # Quick connectivity test"
    echo "  $0 --setup       # Include database setup checks"
    echo "  $0 --container   # Test running container"
    echo ""
}

# Helper functions
log_test() {
    ((TOTAL_TESTS++))
    echo -n "Testing $1... "
}

log_pass() {
    ((PASSED_TESTS++))
    echo -e "${GREEN}✓ PASS${NC}"
    if [ $# -gt 0 ]; then
        echo "   $1"
    fi
}

log_fail() {
    ((FAILED_TESTS++))
    echo -e "${RED}✗ FAIL${NC}"
    if [ $# -gt 0 ]; then
        echo -e "${RED}   $1${NC}"
    fi
}

log_warn() {
    ((WARNINGS++))
    echo -e "${YELLOW}⚠ WARN${NC}"
    if [ $# -gt 0 ]; then
        echo -e "${YELLOW}   $1${NC}"
    fi
}

log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_section() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
    echo ""
}

# Test functions
test_prerequisites() {
    log_section "Prerequisites Check"

    # Test PostgreSQL client
    log_test "PostgreSQL client availability"
    if command -v psql &> /dev/null; then
        log_pass "psql command found"
    else
        log_fail "psql command not found - install postgresql-client"
        return 1
    fi

    # Test Docker
    log_test "Docker availability"
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log_pass "Docker is running"
        else
            log_fail "Docker is not running - start Docker service"
            return 1
        fi
    else
        log_fail "Docker not found - install Docker"
        return 1
    fi

    # Test Maven
    log_test "Maven availability"
    if command -v mvn &> /dev/null; then
        log_pass "Maven found"
    else
        log_warn "Maven not found - required for building"
    fi

    return 0
}

test_postgresql_service() {
    log_section "PostgreSQL Service Check"

    # Test PostgreSQL service
    log_test "PostgreSQL service status"
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        log_pass "PostgreSQL service is active"
    elif pgrep -x postgres &> /dev/null; then
        log_pass "PostgreSQL process found"
    else
        log_fail "PostgreSQL service not running - start with: sudo systemctl start postgresql"
        return 1
    fi

    # Test port 5432
    log_test "PostgreSQL port 5432"
    if ss -tuln 2>/dev/null | grep -q ":5432 " || netstat -tuln 2>/dev/null | grep -q ":5432 "; then
        log_pass "Port 5432 is listening"
    else
        log_fail "Port 5432 is not listening"
        return 1
    fi

    return 0
}

test_database_connectivity() {
    log_section "Database Connectivity"

    # Test Keycloak database connection
    log_test "Keycloak database connection"
    if PGPASSWORD="$KEYCLOAK_DB_PASSWORD" psql -h localhost -p 5432 -U "$KEYCLOAK_DB_USER" -d "$KEYCLOAK_DB_NAME" -c "SELECT 1;" &> /dev/null; then
        log_pass "Connected to $KEYCLOAK_DB_NAME"
    else
        log_fail "Cannot connect to $KEYCLOAK_DB_NAME"
        echo -e "${RED}   Check: Database exists, user permissions, password${NC}"
        return 1
    fi

    # Test User Storage database connection
    log_test "User Storage database connection"
    if PGPASSWORD="$USER_STORAGE_DB_PASSWORD" psql -h localhost -p 5432 -U "$USER_STORAGE_DB_USER" -d "$USER_STORAGE_DB_NAME" -c "SELECT 1;" &> /dev/null; then
        log_pass "Connected to $USER_STORAGE_DB_NAME"
    else
        log_fail "Cannot connect to $USER_STORAGE_DB_NAME"
        echo -e "${RED}   Check: Database exists, user permissions, password${NC}"
        return 1
    fi

    return 0
}

test_database_permissions() {
    log_section "Database Permissions"

    # Test Keycloak user permissions
    log_test "Keycloak user permissions"
    if PGPASSWORD="$KEYCLOAK_DB_PASSWORD" psql -h localhost -p 5432 -U "$KEYCLOAK_DB_USER" -d "$KEYCLOAK_DB_NAME" -c "CREATE TABLE test_permissions (id int); DROP TABLE test_permissions;" &> /dev/null; then
        log_pass "Keycloak user has CREATE/DROP permissions"
    else
        log_fail "Keycloak user lacks necessary permissions"
        return 1
    fi

    # Test User Storage user permissions
    log_test "User Storage user permissions"
    if PGPASSWORD="$USER_STORAGE_DB_PASSWORD" psql -h localhost -p 5432 -U "$USER_STORAGE_DB_USER" -d "$USER_STORAGE_DB_NAME" -c "CREATE TABLE test_permissions (id int); DROP TABLE test_permissions;" &> /dev/null; then
        log_pass "User Storage user has CREATE/DROP permissions"
    else
        log_warn "User Storage user lacks CREATE/DROP permissions (may be read-only)"
    fi

    return 0
}

test_authuser_table() {
    log_section "User Storage Schema"

    # Get table name from environment or default to v_oidc_users
    AUTHUSER_TABLE="${DB_AUTHUSER_TABLE:-v_oidc_users}"

    # Test if user data table/view exists
    log_test "$AUTHUSER_TABLE table/view existence"
    if PGPASSWORD="$USER_STORAGE_DB_PASSWORD" psql -h localhost -p 5432 -U "$USER_STORAGE_DB_USER" -d "$USER_STORAGE_DB_NAME" -c "\d $AUTHUSER_TABLE" &> /dev/null; then
        log_pass "$AUTHUSER_TABLE table/view exists"
    else
        log_fail "$AUTHUSER_TABLE table/view does not exist"
        echo -e "${RED}   ERROR: $AUTHUSER_TABLE table/view must be created by database administrator${NC}"
        echo -e "${YELLOW}   The obp_mapped database is READ-ONLY for this application${NC}"
        echo -e "${YELLOW}   Environment variable DB_AUTHUSER_TABLE=$AUTHUSER_TABLE${NC}"
        return 1
    fi

    # Test required columns
    log_test "$AUTHUSER_TABLE structure"
    required_columns=("id" "username" "password_pw" "email" "firstname" "lastname")
    missing_columns=()

    for column in "${required_columns[@]}"; do
        if ! PGPASSWORD="$USER_STORAGE_DB_PASSWORD" psql -h localhost -p 5432 -U "$USER_STORAGE_DB_USER" -d "$USER_STORAGE_DB_NAME" -c "\d $AUTHUSER_TABLE" 2>/dev/null | grep -q "$column"; then
            missing_columns+=("$column")
        fi
    done

    if [ ${#missing_columns[@]} -eq 0 ]; then
        log_pass "All required columns present"
    else
        log_fail "Missing columns: ${missing_columns[*]}"
        return 1
    fi

    # Test existing data (read-only table/view)
    log_test "$AUTHUSER_TABLE existing data"
    user_count=$(PGPASSWORD="$USER_STORAGE_DB_PASSWORD" psql -h localhost -p 5432 -U "$USER_STORAGE_DB_USER" -d "$USER_STORAGE_DB_NAME" -t -c "SELECT count(*) FROM $AUTHUSER_TABLE;" 2>/dev/null | tr -d ' ')
    if [ "$user_count" -gt 0 ] 2>/dev/null; then
        log_pass "$user_count users found (READ-ONLY table/view)"
    else
        log_warn "No users in $AUTHUSER_TABLE table/view (READ-ONLY)"
        echo -e "${YELLOW}   NOTE: $AUTHUSER_TABLE is READ-ONLY. Users must be added outside of Keycloak.${NC}"
    fi

    return 0
}

test_environment_configuration() {
    log_section "Environment Configuration"

    # Test .env file
    log_test ".env file"
    if [ -f ".env" ]; then
        log_pass ".env exists"

        # Check key environment variables
        source .env 2>/dev/null || true

        log_test "Environment variables"
        missing_vars=()
        required_vars=("KC_DB_URL" "KC_DB_USERNAME" "KC_DB_PASSWORD" "DB_URL" "DB_USER" "DB_PASSWORD")

        for var in "${required_vars[@]}"; do
            if [ -z "${!var}" ]; then
                missing_vars+=("$var")
            fi
        done

        if [ ${#missing_vars[@]} -eq 0 ]; then
            log_pass "All required variables set"
        else
            log_fail "Missing variables: ${missing_vars[*]}"
            return 1
        fi
    else
        log_fail ".env not found"
        echo -e "${YELLOW}   Create: cp .env.example .env${NC}"
        return 1
    fi

    return 0
}

test_docker_network() {
    log_section "Docker Network Configuration"

    # Test host.docker.internal resolution
    log_test "Docker host networking"
    if docker run --rm --add-host=host.docker.internal:host-gateway alpine:latest ping -c 1 host.docker.internal &> /dev/null; then
        log_pass "host.docker.internal accessible from container"
    else
        log_warn "host.docker.internal may not work - check Docker version"
    fi

    # Test port availability
    log_test "Port availability (8000)"
    if ! ss -tuln 2>/dev/null | grep -q ":8000 " && ! netstat -tuln 2>/dev/null | grep -q ":8000 "; then
        log_pass "Port 8000 available"
    else
        log_warn "Port 8000 in use"
    fi

    log_test "Port availability (8443)"
    if ! ss -tuln 2>/dev/null | grep -q ":8443 " && ! netstat -tuln 2>/dev/null | grep -q ":8443 "; then
        log_pass "Port 8443 available"
    else
        log_warn "Port 8443 in use"
    fi

    return 0
}

test_running_container() {
    log_section "Running Container Tests"

    # Check if container is running
    log_test "Container status"
    if docker ps | grep -q "$CONTAINER_NAME.*Up"; then
        log_pass "Container $CONTAINER_NAME is running"
    else
        log_fail "Container $CONTAINER_NAME not running"
        echo -e "${YELLOW}   Start with: ./sh/run-local-postgres.sh${NC}"
        return 1
    fi

    # Test HTTP endpoint
    log_test "HTTP endpoint health"
    if curl -f http://localhost:8000/health/ready &> /dev/null; then
        log_pass "HTTP health check passed"
    else
        log_warn "HTTP health check failed - container may still be starting"
    fi

    # Test HTTPS endpoint
    log_test "HTTPS endpoint health"
    if curl -k -f https://localhost:8443/health/ready &> /dev/null; then
        log_pass "HTTPS health check passed"
    else
        log_warn "HTTPS health check failed"
    fi

    # Test admin console
    log_test "Admin console accessibility"
    if curl -k -f https://localhost:8443/admin &> /dev/null; then
        log_pass "Admin console accessible"
    else
        log_warn "Admin console not accessible - may still be starting"
    fi

    # Check container logs for errors
    log_test "Container error logs"
    error_count=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -i "error\|exception\|failed" | wc -l)
    if [ "$error_count" -eq 0 ]; then
        log_pass "No errors in container logs"
    else
        log_warn "$error_count errors found in logs"
        echo -e "${YELLOW}   Check: docker logs $CONTAINER_NAME${NC}"
    fi

    return 0
}

test_user_federation() {
    log_section "User Federation Tests"

    # This requires the container to be running
    if ! docker ps | grep -q "$CONTAINER_NAME.*Up"; then
        log_info "Skipping user federation tests - container not running"
        return 0
    fi

    # Wait for Keycloak to be fully ready
    log_test "Keycloak readiness"
    max_wait=60
    wait_time=0
    while [ $wait_time -lt $max_wait ]; do
        if curl -f http://localhost:8000/health/ready &> /dev/null; then
            log_pass "Keycloak is ready"
            break
        fi
        sleep 2
        ((wait_time+=2))
    done

    if [ $wait_time -ge $max_wait ]; then
        log_fail "Keycloak not ready after ${max_wait}s"
        return 1
    fi

    # Test database connectivity from container
    log_test "Container-to-database connectivity"
    if docker exec "$CONTAINER_NAME" sh -c "nc -z host.docker.internal 5432" &> /dev/null; then
        log_pass "Container can reach PostgreSQL"
    else
        log_fail "Container cannot reach PostgreSQL"
        return 1
    fi

    log_info "Manual user federation test:"
    echo "  1. Go to https://localhost:8443/admin"
    echo "  2. Login with admin/admin"
    echo "  3. Navigate to User Federation"
    echo "  4. Verify 'obp-keycloak-provider' is listed"
    echo "  5. Test user sync and authentication"

    return 0
}

test_cleanup() {
    log_section "Cleanup and Recovery"

    log_info "Container management commands:"
    echo "  View logs:    docker logs -f $CONTAINER_NAME"
    echo "  Stop:         docker stop $CONTAINER_NAME"
    echo "  Remove:       docker rm $CONTAINER_NAME"
    echo "  Restart:      docker restart $CONTAINER_NAME"

    log_info "Database management commands:"
    echo "  Keycloak DB:  PGPASSWORD=f psql -h localhost -p 5432 -U keycloak -d keycloakdb"
    echo "  User Storage: PGPASSWORD=f psql -h localhost -p 5432 -U obp -d obp_mapped"

    log_info "Troubleshooting commands:"
    echo "  Test setup:   ./sh/test-local-postgres-setup.sh"
    echo "  Run setup:    ./sh/run-local-postgres.sh --validate"
    echo "  View docs:    cat docs/LOCAL_POSTGRESQL_SETUP.md"
}

# Main execution
main() {
    # Default options
    QUICK_TEST=false
    FULL_TEST=true
    INCLUDE_SETUP=false
    TEST_CONTAINER=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick|-q)
                QUICK_TEST=true
                FULL_TEST=false
                shift
                ;;
            --full|-f)
                FULL_TEST=true
                QUICK_TEST=false
                shift
                ;;
            --setup|-s)
                INCLUDE_SETUP=true
                shift
                ;;
            --container|-c)
                TEST_CONTAINER=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done

    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}  OBP Keycloak Provider - Local PostgreSQL Test ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""

    if [ "$QUICK_TEST" = true ]; then
        echo -e "${BLUE}Running quick test suite...${NC}"
    else
        echo -e "${BLUE}Running full test suite...${NC}"
    fi
    echo ""

    # Run tests
    local test_failed=false

    # Basic tests
    test_prerequisites || test_failed=true
    test_postgresql_service || test_failed=true
    test_database_connectivity || test_failed=true

    if [ "$QUICK_TEST" = false ]; then
        # Full test suite
        test_database_permissions || test_failed=true
        test_authuser_table || test_failed=true
        test_environment_configuration || test_failed=true
        test_docker_network || test_failed=true

        if [ "$INCLUDE_SETUP" = true ]; then
            test_user_federation || test_failed=true
        fi

        if [ "$TEST_CONTAINER" = true ]; then
            test_running_container || test_failed=true
        fi

        test_cleanup
    fi

    # Summary
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}              Test Summary                      ${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo -e "Warnings:     ${YELLOW}$WARNINGS${NC}"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        if [ $WARNINGS -gt 0 ]; then
            echo -e "${YELLOW}Note: $WARNINGS warnings detected - review above${NC}"
        fi
        echo ""
        echo "Next steps:"
        echo "  1. Run: ./sh/run-local-postgres.sh --validate"
        echo "  2. Access: https://localhost:8443/admin"
        echo "  3. Test user federation in admin console"
        exit 0
    else
        echo -e "${RED}❌ $FAILED_TESTS tests failed!${NC}"
        echo ""
        echo "Recommended actions:"
        echo "  1. Review failed tests above"
        echo "  2. Check docs/LOCAL_POSTGRESQL_SETUP.md"
        echo "  3. Ensure PostgreSQL is running and configured"
        echo "  4. Verify database permissions and table structure"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
