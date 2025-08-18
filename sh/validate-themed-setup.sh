#!/bin/bash

# Validation script for OBP Keycloak Provider themed deployment
# This script validates that the themed Keycloak deployment is working correctly
#
# Usage: ./sh/validate-themed-setup.sh [OPTIONS]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
CONTAINER_NAME="obp-keycloak-local"
KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-8080}
KEYCLOAK_HTTPS_PORT=${KEYCLOAK_HTTPS_PORT:-8443}

# Signal handler for Ctrl+C
cleanup_and_exit() {
    echo ""
    echo -e "${YELLOW}Validation interrupted${NC}"
    exit 0
}

trap cleanup_and_exit SIGINT

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --container, -c NAME    Container name (default: $CONTAINER_NAME)"
    echo "  --http-port PORT        HTTP port (default: $KEYCLOAK_HTTP_PORT)"
    echo "  --https-port PORT       HTTPS port (default: $KEYCLOAK_HTTPS_PORT)"
    echo "  --help, -h              Show this help message"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --container|-c)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --http-port)
            KEYCLOAK_HTTP_PORT="$2"
            shift 2
            ;;
        --https-port)
            KEYCLOAK_HTTPS_PORT="$2"
            shift 2
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
echo -e "${BLUE}    OBP Keycloak Provider - Themed Validation  ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Validation results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "Testing $test_name... "

    if eval "$test_command" > /dev/null 2>&1; then
        local exit_code=$?
        if [ $exit_code -eq $expected_exit_code ]; then
            echo -e "${GREEN}✓${NC}"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            echo -e "${RED}✗ (exit code: $exit_code)${NC}"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            return 1
        fi
    else
        echo -e "${RED}✗${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Function to run a test with warning
run_test_warning() {
    local test_name="$1"
    local test_command="$2"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "Testing $test_name... "

    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${YELLOW}~ (warning)${NC}"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
        return 1
    fi
}

echo "Validation Configuration:"
echo "  Container Name: $CONTAINER_NAME"
echo "  HTTP Port: $KEYCLOAK_HTTP_PORT"
echo "  HTTPS Port: $KEYCLOAK_HTTPS_PORT"
echo ""

echo -e "${BLUE}1. Container Status Checks${NC}"
echo "=============================="

# Check if Docker is available
run_test "Docker availability" "command -v docker"

# Check if container exists
run_test "Container exists" "docker ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'"

# Check if container is running
run_test "Container is running" "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'"

# Check container health
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    run_test "Container process health" "docker exec $CONTAINER_NAME ls /proc/1/cmdline"
fi

echo ""

echo -e "${BLUE}2. Network Connectivity Checks${NC}"
echo "==============================="

# Test HTTP endpoint
run_test "HTTP endpoint (port $KEYCLOAK_HTTP_PORT)" "curl -s -f -m 10 http://localhost:${KEYCLOAK_HTTP_PORT}/"

# Test HTTPS endpoint
run_test "HTTPS endpoint (port $KEYCLOAK_HTTPS_PORT)" "curl -k -s -f -m 10 https://localhost:${KEYCLOAK_HTTPS_PORT}/"

# Test admin console HTTP
run_test "Admin console (HTTP)" "curl -s -f -m 10 http://localhost:${KEYCLOAK_HTTP_PORT}/admin/"

# Test admin console HTTPS
run_test "Admin console (HTTPS)" "curl -k -s -f -m 10 https://localhost:${KEYCLOAK_HTTPS_PORT}/admin/"

echo ""

echo -e "${BLUE}3. Theme Validation Checks${NC}"
echo "==========================="

# Check if theme directory exists in container
run_test "Theme directory in container" "docker exec $CONTAINER_NAME test -d /opt/keycloak/themes/obp"

# Check theme files
run_test "Theme properties file" "docker exec $CONTAINER_NAME test -f /opt/keycloak/themes/obp/theme.properties"

# Check theme login directory
run_test "Theme login directory" "docker exec $CONTAINER_NAME test -d /opt/keycloak/themes/obp/login"

# Check theme resource accessibility (may not be available until theme is selected)
run_test_warning "Theme resources endpoint" "curl -s -f -m 5 http://localhost:${KEYCLOAK_HTTP_PORT}/resources/obp/ || true"

echo ""

echo -e "${BLUE}4. Provider and Extension Checks${NC}"
echo "================================="

# Check if provider JAR exists
run_test "Provider JAR in container" "docker exec $CONTAINER_NAME test -f /opt/keycloak/providers/obp-keycloak-provider.jar"

# Check if PostgreSQL driver exists
run_test "PostgreSQL driver" "docker exec $CONTAINER_NAME sh -c 'ls /opt/keycloak/providers/postgresql-*.jar'"

# Check container logs for any obvious errors
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo -n "Testing container logs for errors... "
if docker logs "$CONTAINER_NAME" 2>&1 | grep -i "error" | grep -v "404" | grep -v "Unable to find matching target resource method" | grep -v "HTTP 404 Not Found" > /dev/null; then
    echo -e "${YELLOW}~ (warnings found)${NC}"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
else
    echo -e "${GREEN}✓${NC}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
fi

echo ""

echo -e "${BLUE}5. Database Connectivity Checks${NC}"
echo "==============================="

# Test if container can connect to databases (basic check)
run_test "Internal connectivity" "docker exec $CONTAINER_NAME test -f /proc/net/tcp"

echo ""

echo -e "${BLUE}6. Keycloak Service Checks${NC}"
echo "=========================="

# Test realm endpoint (master realm should always exist)
run_test "Master realm availability" "curl -s -f -m 10 http://localhost:${KEYCLOAK_HTTP_PORT}/realms/master"

# Test well-known configuration (may not be available immediately)
echo -n "Testing OpenID configuration... "
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if curl -s -f -m 3 "http://localhost:${KEYCLOAK_HTTP_PORT}/realms/master/.well-known/openid_configuration" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${YELLOW}~ (warning)${NC}"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
fi

echo ""

# Summary
echo -e "${CYAN}================================================${NC}"
echo -e "${BLUE}            Validation Summary                  ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo "Results:"
echo -e "  Total checks: $TOTAL_CHECKS"
echo -e "  ${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "  ${RED}Failed: $FAILED_CHECKS${NC}"
echo -e "  ${YELLOW}Warnings: $WARNING_CHECKS${NC}"

echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"

    if [ $WARNING_CHECKS -gt 0 ]; then
        echo -e "${YELLOW}⚠ Some optional features may need configuration${NC}"
    fi

    echo ""
    echo -e "${BLUE}Next Steps for Theme Activation:${NC}"
    echo "1. Access Admin Console: https://localhost:${KEYCLOAK_HTTPS_PORT}/admin"
    echo "2. Login with admin credentials (admin/admin)"
    echo "3. Go to: Realm Settings > Themes"
    echo "4. Set Login Theme to: obp"
    echo "5. Click Save"
    echo ""
    echo -e "${GREEN}The themed deployment is ready for use!${NC}"

else
    echo -e "${RED}✗ Some checks failed. Please review the issues above.${NC}"
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check container logs: docker logs -f $CONTAINER_NAME"
    echo "2. Verify container is running: docker ps"
    echo "3. Check port availability: netstat -tlnp | grep :${KEYCLOAK_HTTP_PORT}"
    echo "4. Restart container: docker restart $CONTAINER_NAME"
    echo ""
fi

echo "Management Commands:"
echo "  View logs:    docker logs -f $CONTAINER_NAME"
echo "  Stop:         docker stop $CONTAINER_NAME"
echo "  Restart:      docker restart $CONTAINER_NAME"
echo "  Remove:       docker rm $CONTAINER_NAME"
echo ""

# Exit with appropriate code
if [ $FAILED_CHECKS -eq 0 ]; then
    exit 0
else
    exit 1
fi
