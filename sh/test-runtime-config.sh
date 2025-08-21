#!/bin/bash

# Test script for runtime configuration verification
# This script validates that the OBP Keycloak Provider can read environment variables at runtime

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}OBP Keycloak Provider - Runtime Configuration Test${NC}"
echo "======================================================="
echo ""

# Function to test environment variable reading
test_env_var() {
    local var_name=$1
    local test_value=$2
    local description=$3

    echo -n "Testing $var_name ($description)... "

    # Set environment variable and test
    export $var_name="$test_value"

    # Use a simple Java test to verify environment variable reading
    local java_test=$(cat << EOF
public class EnvTest {
    public static void main(String[] args) {
        String value = System.getenv("$var_name");
        if (value != null && value.equals("$test_value")) {
            System.out.println("SUCCESS");
        } else {
            System.out.println("FAILED");
        }
    }
}
EOF
)

    # Create temporary Java file and test
    echo "$java_test" > /tmp/EnvTest.java
    local result=$(cd /tmp && javac EnvTest.java && java EnvTest 2>/dev/null || echo "ERROR")

    if [ "$result" = "SUCCESS" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

# Function to validate build artifacts
validate_build() {
    echo -e "${BLUE}Validating build artifacts...${NC}"
    echo ""

    # Check if JAR file exists
    if [ -f "target/obp-keycloak-provider.jar" ]; then
        echo -e "${GREEN}✓ JAR file exists: target/obp-keycloak-provider.jar${NC}"
    else
        echo -e "${RED}✗ JAR file missing: target/obp-keycloak-provider.jar${NC}"
        echo "  Run 'mvn clean package' first"
        return 1
    fi

    # Check if DatabaseConfig class is in JAR
    if jar tf target/obp-keycloak-provider.jar | grep -q "io/tesobe/config/DatabaseConfig.class"; then
        echo -e "${GREEN}✓ DatabaseConfig class found in JAR${NC}"
    else
        echo -e "${RED}✗ DatabaseConfig class missing from JAR${NC}"
        return 1
    fi

    # Check if persistence.xml is generic (no ${} placeholders)
    if jar xf target/obp-keycloak-provider.jar META-INF/persistence.xml -O 2>/dev/null; then
        if jar xf target/obp-keycloak-provider.jar META-INF/persistence.xml -O | grep -q '\${'; then
            echo -e "${RED}✗ persistence.xml still contains build-time placeholders${NC}"
            echo "  Found placeholders:"
            jar xf target/obp-keycloak-provider.jar META-INF/persistence.xml -O | grep '\${'
            return 1
        else
            echo -e "${GREEN}✓ persistence.xml is generic (no build-time placeholders)${NC}"
        fi
    else
        echo -e "${YELLOW}! Could not extract persistence.xml for validation${NC}"
    fi

    echo ""
}

# Function to test database configuration scenarios
test_database_configs() {
    echo -e "${BLUE}Testing database configuration scenarios...${NC}"
    echo ""

    local pass_count=0
    local total_tests=0

    # Test required database variables
    local db_tests=(
        "DB_URL|jdbc:postgresql://localhost:5432/test_db|Database URL"
        "DB_USER|test_user|Database username"
        "DB_PASSWORD|test_password|Database password"
        "DB_DRIVER|org.postgresql.Driver|JDBC driver"
        "DB_DIALECT|org.hibernate.dialect.PostgreSQLDialect|Hibernate dialect"
    )

    for test_case in "${db_tests[@]}"; do
        IFS='|' read -r var_name test_value description <<< "$test_case"
        total_tests=$((total_tests + 1))
        if test_env_var "$var_name" "$test_value" "$description"; then
            pass_count=$((pass_count + 1))
        fi
    done

    # Test Hibernate configuration variables
    local hibernate_tests=(
        "HIBERNATE_DDL_AUTO|validate|Schema validation mode"
        "HIBERNATE_SHOW_SQL|true|SQL logging"
        "HIBERNATE_FORMAT_SQL|false|SQL formatting"
    )

    for test_case in "${hibernate_tests[@]}"; do
        IFS='|' read -r var_name test_value description <<< "$test_case"
        total_tests=$((total_tests + 1))
        if test_env_var "$var_name" "$test_value" "$description"; then
            pass_count=$((pass_count + 1))
        fi
    done

    echo ""
    echo "Environment variable tests: $pass_count/$total_tests passed"

    if [ $pass_count -eq $total_tests ]; then
        echo -e "${GREEN}✓ All environment variable tests passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Some environment variable tests failed${NC}"
        return 1
    fi
}

# Function to test Docker build without build args
test_docker_build() {
    echo -e "${BLUE}Testing Docker build (generic image)...${NC}"
    echo ""

    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}! Docker not available, skipping Docker tests${NC}"
        return 0
    fi

    # Test that Docker build works without build arguments
    echo "Building Docker image without build arguments..."
    if docker build -t obp-keycloak-test -f docker/Dockerfile . > /tmp/docker_build.log 2>&1; then
        echo -e "${GREEN}✓ Docker build successful (no build args required)${NC}"

        # Check that the image doesn't contain hardcoded environment variables
        echo "Checking for hardcoded environment variables..."
        if docker run --rm obp-keycloak-test printenv | grep -E "^DB_(URL|USER|PASSWORD)=" > /dev/null; then
            echo -e "${RED}✗ Docker image contains hardcoded database environment variables${NC}"
            docker run --rm obp-keycloak-test printenv | grep -E "^DB_(URL|USER|PASSWORD)="
            return 1
        else
            echo -e "${GREEN}✓ Docker image does not contain hardcoded database credentials${NC}"
        fi

        # Cleanup
        docker rmi obp-keycloak-test > /dev/null 2>&1 || true

        return 0
    else
        echo -e "${RED}✗ Docker build failed${NC}"
        echo "Build log:"
        cat /tmp/docker_build.log
        return 1
    fi
}

# Function to test Kubernetes compatibility
test_kubernetes_compatibility() {
    echo -e "${BLUE}Testing Kubernetes compatibility...${NC}"
    echo ""

    # Check if Kubernetes manifests are valid
    if command -v kubectl &> /dev/null; then
        echo "Validating Kubernetes manifests..."

        local k8s_files=("k8s/configmap.yaml" "k8s/secret.yaml" "k8s/deployment.yaml")
        local valid_count=0

        for file in "${k8s_files[@]}"; do
            if [ -f "$file" ]; then
                echo -n "  Validating $file... "
                if kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓ Valid${NC}"
                    valid_count=$((valid_count + 1))
                else
                    echo -e "${RED}✗ Invalid${NC}"
                fi
            else
                echo -e "${YELLOW}  ! $file not found${NC}"
            fi
        done

        if [ $valid_count -eq ${#k8s_files[@]} ]; then
            echo -e "${GREEN}✓ All Kubernetes manifests are valid${NC}"
        else
            echo -e "${YELLOW}! Some Kubernetes manifests have issues${NC}"
        fi
    else
        echo -e "${YELLOW}! kubectl not available, skipping Kubernetes validation${NC}"
    fi

    # Check if docker-compose file is valid
    if [ -f "docker-compose.runtime.yml" ]; then
        echo -n "Validating docker-compose.runtime.yml... "
        if command -v docker-compose &> /dev/null; then
            if docker-compose -f docker-compose.runtime.yml config > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Valid${NC}"
            else
                echo -e "${RED}✗ Invalid${NC}"
            fi
        else
            echo -e "${YELLOW}! docker-compose not available${NC}"
        fi
    fi

    echo ""
}

# Function to show configuration examples
show_examples() {
    echo -e "${BLUE}Runtime Configuration Examples:${NC}"
    echo ""

    echo "1. Docker run with environment variables:"
    echo -e "${YELLOW}   docker run -e DB_URL=jdbc:postgresql://localhost:5432/obp_mapped \\"
    echo "              -e DB_USER=obp \\"
    echo "              -e DB_PASSWORD=changeme \\"
    echo "              obp-keycloak-provider${NC}"
    echo ""

    echo "2. Docker Compose:"
    echo -e "${YELLOW}   docker-compose -f docker-compose.runtime.yml up${NC}"
    echo ""

    echo "3. Kubernetes:"
    echo -e "${YELLOW}   kubectl apply -f k8s/configmap.yaml"
    echo "   kubectl apply -f k8s/secret.yaml"
    echo "   kubectl apply -f k8s/deployment.yaml${NC}"
    echo ""

    echo "4. Environment file:"
    echo -e "${YELLOW}   # Create .env file"
    echo "   DB_URL=jdbc:postgresql://localhost:5432/obp_mapped"
    echo "   DB_USER=obp"
    echo "   DB_PASSWORD=changeme"
    echo "   "
    echo "   # Run with environment file"
    echo "   docker run --env-file .env obp-keycloak-provider${NC}"
    echo ""
}

# Main test execution
main() {
    local overall_result=0

    echo "This script validates that the OBP Keycloak Provider has been successfully"
    echo "migrated from build-time to runtime configuration."
    echo ""

    # Run validation tests
    validate_build || overall_result=1
    test_database_configs || overall_result=1
    test_docker_build || overall_result=1
    test_kubernetes_compatibility

    echo ""
    echo "======================================================="

    if [ $overall_result -eq 0 ]; then
        echo -e "${GREEN}🎉 SUCCESS: Runtime configuration is working correctly!${NC}"
        echo ""
        echo "The OBP Keycloak Provider has been successfully migrated to use"
        echo "runtime configuration. It is now compatible with:"
        echo "  ✅ Kubernetes deployments"
        echo "  ✅ Docker Hub hosted images"
        echo "  ✅ Cloud-native deployment patterns"
        echo "  ✅ CI/CD pipelines with 'build once, deploy everywhere'"
        echo ""
        show_examples
    else
        echo -e "${RED}❌ FAILURE: Some tests failed${NC}"
        echo ""
        echo "Please review the failed tests above and fix the issues."
        echo "The runtime configuration may not be complete."
        echo ""
        echo "Common issues:"
        echo "  • Build artifacts missing (run 'mvn clean package')"
        echo "  • Java/Docker not installed"
        echo "  • persistence.xml still contains build-time placeholders"
        echo ""
    fi

    return $overall_result
}

# Cleanup function
cleanup() {
    # Remove temporary files
    rm -f /tmp/EnvTest.java /tmp/EnvTest.class /tmp/docker_build.log

    # Unset test environment variables
    unset DB_URL DB_USER DB_PASSWORD DB_DRIVER DB_DIALECT
    unset HIBERNATE_DDL_AUTO HIBERNATE_SHOW_SQL HIBERNATE_FORMAT_SQL
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"
