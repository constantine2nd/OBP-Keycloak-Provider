#!/bin/bash

# Test Script for Docker Cache Invalidation
# This script verifies that the cache invalidation mechanism works correctly
# when the JAR file changes between builds

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  Docker Cache Invalidation Test                ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Configuration
TEST_IMAGE_TAG="obp-keycloak-test-cache"
DOCKERFILE_PATH="docker/Dockerfile"

# Parse arguments
DOCKERFILE_PATH="docker/Dockerfile"
if [[ "$1" == "--themed" ]]; then
    DOCKERFILE_PATH=".github/Dockerfile_themed"
    TEST_IMAGE_TAG="obp-keycloak-test-cache-themed"
fi

echo "Testing cache invalidation with: $DOCKERFILE_PATH"
echo ""

# Function to build and capture layer info
build_and_analyze() {
    local build_num=$1
    local expected_rebuild=$2

    echo -e "${BLUE}--- Build $build_num ---${NC}"

    # Generate unique timestamp and checksum for this build
    BUILD_TIMESTAMP=$(date +%s)

    if [ -f "target/obp-keycloak-provider.jar" ]; then
        JAR_CHECKSUM=$(sha256sum target/obp-keycloak-provider.jar | cut -d' ' -f1)
    else
        echo -e "${YELLOW}Warning: JAR file not found, using dummy checksum${NC}"
        JAR_CHECKSUM="dummy_checksum_$BUILD_TIMESTAMP"
    fi

    echo "Build timestamp: $BUILD_TIMESTAMP"
    echo "JAR checksum: ${JAR_CHECKSUM:0:12}..."

    # Build with timing
    echo "Building image..."
    start_time=$(date +%s)

    docker build \
        --build-arg BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
        --build-arg JAR_CHECKSUM="$JAR_CHECKSUM" \
        -t "$TEST_IMAGE_TAG:build$build_num" \
        -f "$DOCKERFILE_PATH" \
        . > build_output_$build_num.log 2>&1

    build_result=$?
    end_time=$(date +%s)
    build_duration=$((end_time - start_time))

    if [ $build_result -eq 0 ]; then
        echo -e "${GREEN}✓ Build completed in ${build_duration}s${NC}"
    else
        echo -e "${RED}✗ Build failed${NC}"
        echo "Check build_output_$build_num.log for details"
        return 1
    fi

    # Analyze cache usage from build output
    cached_steps=$(grep -c "Using cache" build_output_$build_num.log 2>/dev/null || echo "0")
    total_steps=$(grep -c "Step " build_output_$build_num.log 2>/dev/null || echo "0")

    echo "Cache analysis:"
    echo "  Cached steps: $cached_steps/$total_steps"
    echo "  Build duration: ${build_duration}s"

    # Check if build info was embedded
    if docker run --rm "$TEST_IMAGE_TAG:build$build_num" cat /opt/keycloak/build-info.txt 2>/dev/null | grep -q "$BUILD_TIMESTAMP"; then
        echo -e "${GREEN}✓ Build info correctly embedded${NC}"
    else
        echo -e "${YELLOW}⚠ Build info not found or incorrect${NC}"
    fi

    # Store results for comparison
    echo "$build_duration" > "build_time_$build_num.txt"
    echo "$cached_steps" > "cached_steps_$build_num.txt"
    echo "$JAR_CHECKSUM" > "jar_checksum_$build_num.txt"

    echo ""
    return 0
}

# Function to modify JAR to simulate changes
simulate_jar_change() {
    echo -e "${BLUE}Simulating JAR file change...${NC}"

    if [ ! -f "target/obp-keycloak-provider.jar" ]; then
        echo -e "${YELLOW}JAR file not found, creating dummy file${NC}"
        mkdir -p target
        echo "dummy content $(date +%s)" > target/obp-keycloak-provider.jar
    else
        # Add a comment to a Java file and rebuild
        echo "// Cache test modification $(date +%s)" >> src/main/java/com/tesobe/obp/UserStorageProvider.java

        echo "Rebuilding Maven project..."
        mvn clean package -DskipTests -q

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ JAR file updated${NC}"
        else
            echo -e "${RED}✗ Maven rebuild failed${NC}"
            return 1
        fi
    fi

    echo ""
}

# Cleanup function
cleanup() {
    echo -e "${BLUE}Cleaning up test artifacts...${NC}"

    # Remove test images
    docker rmi "$TEST_IMAGE_TAG:build1" 2>/dev/null || true
    docker rmi "$TEST_IMAGE_TAG:build2" 2>/dev/null || true

    # Remove test files
    rm -f build_output_*.log
    rm -f build_time_*.txt
    rm -f cached_steps_*.txt
    rm -f jar_checksum_*.txt

    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Trap cleanup on exit
trap cleanup EXIT

# Pre-test checks
echo -e "${BLUE}Pre-test validation:${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker available${NC}"

# Check Dockerfile
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo -e "${RED}✗ Dockerfile not found: $DOCKERFILE_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Dockerfile found${NC}"

# Ensure we have a JAR file
if [ ! -f "target/obp-keycloak-provider.jar" ]; then
    echo -e "${YELLOW}Building initial JAR file...${NC}"
    mvn clean package -DskipTests -q

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Initial Maven build failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ JAR file available${NC}"
echo ""

# Test 1: Initial build (should build everything)
echo -e "${CYAN}Test 1: Initial Build${NC}"
echo "This should build all layers from scratch"
echo ""

if ! build_and_analyze 1 "full_rebuild"; then
    echo -e "${RED}✗ Test 1 failed${NC}"
    exit 1
fi

# Test 2: Rebuild with same JAR (should use cache)
echo -e "${CYAN}Test 2: Rebuild with Same JAR${NC}"
echo "This should reuse cached layers (except timestamp layer)"
echo ""

if ! build_and_analyze 2 "mostly_cached"; then
    echo -e "${RED}✗ Test 2 failed${NC}"
    exit 1
fi

# Test 3: Rebuild with modified JAR (should invalidate cache)
echo -e "${CYAN}Test 3: Modified JAR Build${NC}"
echo "This should invalidate cache after the JAR layer"
echo ""

if ! simulate_jar_change; then
    echo -e "${RED}✗ JAR modification failed${NC}"
    exit 1
fi

if ! build_and_analyze 3 "cache_invalidated"; then
    echo -e "${RED}✗ Test 3 failed${NC}"
    exit 1
fi

# Analysis
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}           Test Results Analysis                ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Read results
build_time_1=$(cat build_time_1.txt 2>/dev/null || echo "0")
build_time_2=$(cat build_time_2.txt 2>/dev/null || echo "0")
build_time_3=$(cat build_time_3.txt 2>/dev/null || echo "0")

cached_steps_1=$(cat cached_steps_1.txt 2>/dev/null || echo "0")
cached_steps_2=$(cat cached_steps_2.txt 2>/dev/null || echo "0")
cached_steps_3=$(cat cached_steps_3.txt 2>/dev/null || echo "0")

jar_checksum_1=$(cat jar_checksum_1.txt 2>/dev/null || echo "unknown")
jar_checksum_2=$(cat jar_checksum_2.txt 2>/dev/null || echo "unknown")
jar_checksum_3=$(cat jar_checksum_3.txt 2>/dev/null || echo "unknown")

echo "Build Times:"
echo "  Initial build:    ${build_time_1}s"
echo "  Same JAR build:   ${build_time_2}s"
echo "  Changed JAR build: ${build_time_3}s"
echo ""

echo "Cache Efficiency:"
echo "  Initial build:    ${cached_steps_1} cached steps"
echo "  Same JAR build:   ${cached_steps_2} cached steps"
echo "  Changed JAR build: ${cached_steps_3} cached steps"
echo ""

echo "JAR Checksums:"
echo "  Build 1: ${jar_checksum_1:0:12}..."
echo "  Build 2: ${jar_checksum_2:0:12}..."
echo "  Build 3: ${jar_checksum_3:0:12}..."
echo ""

# Validation
echo -e "${BLUE}Validation Results:${NC}"

# Test 1: Build 2 should be faster than Build 1 (more caching)
if [ "$build_time_2" -lt "$build_time_1" ] && [ "$cached_steps_2" -gt "$cached_steps_1" ]; then
    echo -e "${GREEN}✓ Cache reuse working (Build 2 faster and more cached)${NC}"
else
    echo -e "${YELLOW}⚠ Cache reuse questionable (Build 2: ${build_time_2}s vs Build 1: ${build_time_1}s)${NC}"
fi

# Test 2: JAR checksums should differ between builds 2 and 3
if [ "$jar_checksum_2" != "$jar_checksum_3" ]; then
    echo -e "${GREEN}✓ JAR change detected (different checksums)${NC}"
else
    echo -e "${RED}✗ JAR change not detected (same checksums)${NC}"
fi

# Test 3: Build 3 should have less caching than Build 2 (cache invalidation)
if [ "$cached_steps_3" -lt "$cached_steps_2" ]; then
    echo -e "${GREEN}✓ Cache invalidation working (Build 3 less cached)${NC}"
else
    echo -e "${YELLOW}⚠ Cache invalidation questionable (Build 3: $cached_steps_3 vs Build 2: $cached_steps_2)${NC}"
fi

# Overall assessment
echo ""
if [ "$jar_checksum_2" != "$jar_checksum_3" ] && [ "$cached_steps_3" -lt "$cached_steps_2" ]; then
    echo -e "${GREEN}✓ Cache invalidation mechanism working correctly!${NC}"
    echo ""
    echo "Summary:"
    echo "• JAR changes are properly detected"
    echo "• Cache invalidation triggers on JAR modifications"
    echo "• Build performance benefits from caching when JAR unchanged"
    echo ""
    echo -e "${GREEN}The CI/CD script will rebuild containers when code changes.${NC}"
else
    echo -e "${YELLOW}⚠ Cache invalidation mechanism needs review${NC}"
    echo ""
    echo "Issues detected:"
    if [ "$jar_checksum_2" == "$jar_checksum_3" ]; then
        echo "• JAR changes not detected properly"
    fi
    if [ "$cached_steps_3" -ge "$cached_steps_2" ]; then
        echo "• Cache not invalidating on JAR changes"
    fi
    echo ""
    echo -e "${YELLOW}Consider reviewing Dockerfile cache invalidation logic${NC}"
fi

echo ""
echo -e "${CYAN}Test completed. Check build_output_*.log for detailed build logs.${NC}"
