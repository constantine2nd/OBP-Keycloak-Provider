#!/bin/bash

# Deployment Scripts Comparison Utility
# This script helps you understand the differences between deployment approaches

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  OBP Keycloak Deployment Scripts Comparison    ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if both scripts exist
ORIGINAL_SCRIPT="sh/run-local-postgres.sh"
CICD_SCRIPT="sh/run-local-postgres-cicd.sh"

if [ ! -f "$ORIGINAL_SCRIPT" ]; then
    echo -e "${RED}✗ Original script not found: $ORIGINAL_SCRIPT${NC}"
    exit 1
fi

if [ ! -f "$CICD_SCRIPT" ]; then
    echo -e "${RED}✗ CI/CD script not found: $CICD_SCRIPT${NC}"
    exit 1
fi

# Function to check script features
check_feature() {
    local script=$1
    local pattern=$2
    local feature=$3

    if grep -q "$pattern" "$script"; then
        echo -e "  ✅ $feature"
    else
        echo -e "  ❌ $feature"
    fi
}

echo -e "${BLUE}Script Feature Comparison:${NC}"
echo ""

echo -e "${YELLOW}Original Script (run-local-postgres.sh):${NC}"
check_feature "$ORIGINAL_SCRIPT" "FORCE_BUILD=false" "Conditional building"
check_feature "$ORIGINAL_SCRIPT" "--build" "Build flag support"
check_feature "$ORIGINAL_SCRIPT" "cleanup_and_exit" "Interrupt handling"
check_feature "$ORIGINAL_SCRIPT" "show_usage" "Usage documentation"
check_feature "$ORIGINAL_SCRIPT" "TEST_CONNECTIONS" "Database testing"
check_feature "$ORIGINAL_SCRIPT" "VALIDATE_SETUP" "Setup validation"
check_feature "$ORIGINAL_SCRIPT" "docker images.*grep" "Image existence check"

echo ""
echo -e "${YELLOW}CI/CD Script (run-local-postgres-cicd.sh):${NC}"
check_feature "$CICD_SCRIPT" "BUILD_TIMESTAMP" "Build timestamp tracking"
check_feature "$CICD_SCRIPT" "JAR_CHECKSUM" "JAR checksum validation"
check_feature "$CICD_SCRIPT" "--no-cache" "Forced cache invalidation"
check_feature "$CICD_SCRIPT" "mvn clean package" "Always build Maven"
check_feature "$CICD_SCRIPT" "docker stop.*docker rm" "Always replace container"
check_feature "$CICD_SCRIPT" "\[1/8\]" "Pipeline steps"
check_feature "$CICD_SCRIPT" "exit 1" "Fail-fast error handling"

echo ""
echo -e "${BLUE}Key Differences:${NC}"
echo ""

echo -e "${CYAN}Build Strategy:${NC}"
echo "  Original: Conditional building with --build flag"
echo "  CI/CD:    Always builds Maven project and Docker image"
echo ""

echo -e "${CYAN}Container Handling:${NC}"
echo "  Original: Optionally stops/removes existing container"
echo "  CI/CD:    Always stops and removes existing container"
echo ""

echo -e "${CYAN}Cache Management:${NC}"
echo "  Original: Uses Docker layer caching for efficiency"
echo "  CI/CD:    Forces rebuild with --no-cache and invalidation"
echo ""

echo -e "${CYAN}Error Handling:${NC}"
echo "  Original: Continues on some errors, provides guidance"
echo "  CI/CD:    Fails fast on any error for automated environments"
echo ""

echo -e "${CYAN}Output Style:${NC}"
echo "  Original: Verbose, interactive, user-friendly"
echo "  CI/CD:    Streamlined, pipeline-friendly, structured"
echo ""

# Performance comparison
echo -e "${BLUE}Performance Characteristics:${NC}"
echo ""

# Get script sizes
ORIGINAL_SIZE=$(wc -l < "$ORIGINAL_SCRIPT" 2>/dev/null || echo "Unknown")
CICD_SIZE=$(wc -l < "$CICD_SCRIPT" 2>/dev/null || echo "Unknown")

echo "Script Complexity:"
echo "  Original: $ORIGINAL_SIZE lines"
echo "  CI/CD:    $CICD_SIZE lines"
echo ""

echo "Typical Build Time:"
echo "  Original: 30s - 2m (depending on cache state)"
echo "  CI/CD:    1-3m (always full rebuild)"
echo ""

echo "Resource Usage:"
echo "  Original: Lower (uses caching)"
echo "  CI/CD:    Higher (forces rebuild)"
echo ""

# Usage recommendations
echo -e "${BLUE}Usage Recommendations:${NC}"
echo ""

echo -e "${GREEN}Use Original Script When:${NC}"
echo "  • Local development with frequent iterations"
echo "  • Manual testing and debugging"
echo "  • Resource-constrained environments"
echo "  • You want to preserve running containers"
echo "  • Interactive development workflow"
echo ""

echo -e "${GREEN}Use CI/CD Script When:${NC}"
echo "  • Automated deployment pipelines"
echo "  • Continuous integration environments"
echo "  • Production deployments"
echo "  • Testing scenarios requiring clean state"
echo "  • Consistent, repeatable deployments"
echo ""

# Migration guidance
echo -e "${BLUE}Migration Guide:${NC}"
echo ""

echo "To switch from Original to CI/CD:"
echo "  1. Update your automation scripts:"
echo "     OLD: ./sh/run-local-postgres.sh --build --themed"
echo "     NEW: ./sh/run-local-postgres-cicd.sh --themed"
echo ""
echo "  2. Remove build flags (always builds now)"
echo "  3. Update CI/CD pipelines"
echo "  4. Test thoroughly in your environment"
echo ""

echo "To switch from CI/CD to Original:"
echo "  1. Add appropriate flags:"
echo "     ./sh/run-local-postgres.sh --build --themed"
echo "  2. Consider using --validate for first run"
echo "  3. Leverage caching for faster subsequent builds"
echo ""

# Environment analysis
if [ -f ".env.local" ]; then
    echo -e "${BLUE}Current Environment:${NC}"
    echo -e "${GREEN}✓ .env.local file exists${NC}"

    # Check for common variables
    source .env.local 2>/dev/null || true

    if [ -n "$KEYCLOAK_ADMIN" ]; then
        echo "✓ Keycloak admin configured: $KEYCLOAK_ADMIN"
    else
        echo "⚠ Keycloak admin not configured"
    fi

    if [ -n "$KC_DB_URL" ]; then
        echo "✓ Keycloak database configured"
    else
        echo "⚠ Keycloak database not configured"
    fi

    if [ -n "$DB_URL" ]; then
        echo "✓ User storage database configured"
    else
        echo "⚠ User storage database not configured"
    fi
else
    echo -e "${YELLOW}⚠ .env.local file not found${NC}"
    echo "Both scripts require this file. Create it from env.sample"
fi

echo ""

# Docker environment check
echo -e "${BLUE}Docker Environment:${NC}"
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓ Docker is running${NC}"

        # Check for existing containers
        if docker ps -q --filter "name=obp-keycloak-local" | grep -q .; then
            echo "ℹ Existing container is running"
            echo "  Original script: Will reuse if no --build flag"
            echo "  CI/CD script: Will stop and replace"
        else
            echo "ℹ No existing container found"
        fi

        # Check for existing images
        if docker images | grep -q "obp-keycloak-provider-local"; then
            echo "ℹ Existing image found"
            echo "  Original script: Will reuse unless --build"
            echo "  CI/CD script: Will rebuild with cache invalidation"
        else
            echo "ℹ No existing image found (both scripts will build)"
        fi
    else
        echo -e "${RED}✗ Docker daemon not running${NC}"
    fi
else
    echo -e "${RED}✗ Docker not installed${NC}"
fi

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}           Comparison Complete                   ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "For detailed documentation:"
echo "  Original: README.md"
echo "  CI/CD:    docs/CICD_DEPLOYMENT.md"
echo ""
echo "Quick start:"
echo "  Development: ./sh/run-local-postgres.sh --themed"
echo "  CI/CD:       ./sh/run-local-postgres-cicd.sh --themed"
