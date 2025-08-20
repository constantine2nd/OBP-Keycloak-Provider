#!/bin/bash

# Test Script for Theme Validation in CI/CD Deployment
# This script tests the theme validation logic without running full deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}  Theme Validation Test Suite                   ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Test configuration
TEST_DIR="test_themes_temp"
ORIGINAL_THEME_DIR=""

# Cleanup function
cleanup() {
    echo -e "${BLUE}Cleaning up test artifacts...${NC}"
    if [ -n "$ORIGINAL_THEME_DIR" ] && [ -d "$ORIGINAL_THEME_DIR" ]; then
        echo "Restoring original theme directory..."
        rm -rf "themes"
        mv "$ORIGINAL_THEME_DIR" "themes"
    fi
    rm -rf "$TEST_DIR"
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Trap cleanup on exit
trap cleanup EXIT

# Function to create test theme structure
create_test_theme() {
    local test_name=$1
    local theme_dir="$TEST_DIR/themes/obp"

    echo -e "${BLUE}Setting up test: $test_name${NC}"

    # Backup original theme if it exists
    if [ -d "themes" ] && [ -z "$ORIGINAL_THEME_DIR" ]; then
        ORIGINAL_THEME_DIR="themes_backup_$$"
        mv "themes" "$ORIGINAL_THEME_DIR"
    fi

    # Clean previous test
    rm -rf "$TEST_DIR" themes
    mkdir -p "$theme_dir/login/resources/css"
    mkdir -p "$theme_dir/login/messages"
}

# Function to test validation (extract from CI/CD script)
validate_theme_files() {
    echo -e "${CYAN}Validating themed deployment requirements...${NC}"

    DOCKERFILE_PATH=".github/Dockerfile_themed"

    # Check if themed Dockerfile exists
    if [ ! -f "$DOCKERFILE_PATH" ]; then
        echo -e "${RED}✗ Themed Dockerfile not found: $DOCKERFILE_PATH${NC}"
        echo "Expected location: .github/Dockerfile_themed"
        return 1
    fi

    # Check if theme directory exists
    if [ ! -d "themes/obp" ]; then
        echo -e "${RED}✗ Theme directory not found: themes/obp${NC}"
        echo "Themed deployment requires the obp theme directory"
        echo "Create it with: mkdir -p themes/obp/login"
        return 1
    fi

    # Check theme.properties
    if [ ! -f "themes/obp/theme.properties" ]; then
        echo -e "${RED}✗ Theme configuration not found: themes/obp/theme.properties${NC}"
        return 1
    fi

    # Validate theme.properties content
    echo -n "Validating theme.properties content... "
    if grep -q "parent=base" "themes/obp/theme.properties" &&
       grep -q "styles=" "themes/obp/theme.properties"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Invalid theme.properties${NC}"
        echo "theme.properties must contain 'parent=base' and 'styles=' entries"
        return 1
    fi

    # Check login theme directory
    if [ ! -d "themes/obp/login" ]; then
        echo -e "${RED}✗ Login theme directory not found: themes/obp/login${NC}"
        return 1
    fi

    # Check required login template files
    required_templates=("login.ftl" "template.ftl")
    missing_templates=()
    for template in "${required_templates[@]}"; do
        if [ ! -f "themes/obp/login/$template" ]; then
            missing_templates+=("$template")
        fi
    done

    if [ ${#missing_templates[@]} -ne 0 ]; then
        echo -e "${RED}✗ Missing login templates: ${missing_templates[*]}${NC}"
        echo "Required templates in themes/obp/login/:"
        for template in "${required_templates[@]}"; do
            echo "  - $template"
        done
        return 1
    fi

    # Check for resources directory
    echo -n "Checking theme resources... "
    if [ -d "themes/obp/login/resources" ]; then
        echo -e "${GREEN}✓ Resources directory found${NC}"

        # Check for CSS files
        if [ -d "themes/obp/login/resources/css" ]; then
            css_count=$(find "themes/obp/login/resources/css" -name "*.css" 2>/dev/null | wc -l)
            if [ "$css_count" -gt 0 ]; then
                echo "  Found $css_count CSS file(s)"
            fi
        fi

        # Check for image files
        if [ -d "themes/obp/login/resources/img" ]; then
            img_count=$(find "themes/obp/login/resources/img" -type f 2>/dev/null | wc -l)
            if [ "$img_count" -gt 0 ]; then
                echo "  Found $img_count image file(s)"
            fi
        fi
    else
        echo -e "${YELLOW}~ Resources directory optional${NC}"
    fi

    # Check messages directory for internationalization
    echo -n "Checking internationalization... "
    if [ -d "themes/obp/login/messages" ]; then
        msg_count=$(find "themes/obp/login/messages" -name "messages_*.properties" 2>/dev/null | wc -l)
        if [ "$msg_count" -gt 0 ]; then
            echo -e "${GREEN}✓ Found $msg_count message file(s)${NC}"
        else
            echo -e "${YELLOW}~ No message files found${NC}"
        fi
    else
        echo -e "${YELLOW}~ Messages directory optional${NC}"
    fi

    echo -e "${GREEN}✓ All themed deployment requirements validated${NC}"
    return 0
}

# Test 1: Complete valid theme
echo -e "${CYAN}Test 1: Complete Valid Theme${NC}"
create_test_theme "Complete Valid Theme"

# Create valid theme structure
cp -r "$TEST_DIR/themes" .

# Create theme.properties
cat > themes/obp/theme.properties << 'EOF'
parent=base
styles=css/styles.css
locales=en,de,fr

# OBP Theme Configuration
name=OBP Keycloak Theme
displayName=Open Bank Project
version=1.0.0
EOF

# Create required templates
cat > themes/obp/login/login.ftl << 'EOF'
<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=social.displayInfo>
  <!-- Login form content -->
</@layout.registrationLayout>
EOF

cat > themes/obp/login/template.ftl << 'EOF'
<#macro registrationLayout displayInfo=false>
<!DOCTYPE html>
<html>
<head>
    <title>OBP Login</title>
</head>
<body>
    <#nested>
</body>
</html>
</#macro>
EOF

# Create CSS file
echo "/* OBP Theme Styles */" > themes/obp/login/resources/css/styles.css

# Create message file
echo "loginTitle=Open Bank Project Login" > themes/obp/login/messages/messages_en.properties

if validate_theme_files; then
    echo -e "${GREEN}✓ Test 1 PASSED${NC}"
    TEST1_RESULT="PASS"
else
    echo -e "${RED}✗ Test 1 FAILED${NC}"
    TEST1_RESULT="FAIL"
fi
echo ""

# Test 2: Missing theme.properties
echo -e "${CYAN}Test 2: Missing theme.properties${NC}"
create_test_theme "Missing theme.properties"
cp -r "$TEST_DIR/themes" .

# Create login directory but no theme.properties
mkdir -p themes/obp/login
cat > themes/obp/login/login.ftl << 'EOF'
<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=social.displayInfo>
</@layout.registrationLayout>
EOF

cat > themes/obp/login/template.ftl << 'EOF'
<#macro registrationLayout displayInfo=false>
<!DOCTYPE html>
<html><body><#nested></body></html>
</#macro>
EOF

if validate_theme_files; then
    echo -e "${RED}✗ Test 2 FAILED (should have failed)${NC}"
    TEST2_RESULT="FAIL"
else
    echo -e "${GREEN}✓ Test 2 PASSED (correctly failed validation)${NC}"
    TEST2_RESULT="PASS"
fi
echo ""

# Test 3: Invalid theme.properties content
echo -e "${CYAN}Test 3: Invalid theme.properties Content${NC}"
create_test_theme "Invalid theme.properties"
cp -r "$TEST_DIR/themes" .

# Create invalid theme.properties (missing required fields)
cat > themes/obp/theme.properties << 'EOF'
name=OBP Theme
version=1.0.0
# Missing parent=base and styles=
EOF

# Create required templates
mkdir -p themes/obp/login
cat > themes/obp/login/login.ftl << 'EOF'
<#import "template.ftl" as layout>
<@layout.registrationLayout></@layout.registrationLayout>
EOF

cat > themes/obp/login/template.ftl << 'EOF'
<#macro registrationLayout displayInfo=false>
<html><body><#nested></body></html>
</#macro>
EOF

if validate_theme_files; then
    echo -e "${RED}✗ Test 3 FAILED (should have failed)${NC}"
    TEST3_RESULT="FAIL"
else
    echo -e "${GREEN}✓ Test 3 PASSED (correctly failed validation)${NC}"
    TEST3_RESULT="PASS"
fi
echo ""

# Test 4: Missing required templates
echo -e "${CYAN}Test 4: Missing Required Templates${NC}"
create_test_theme "Missing Templates"
cp -r "$TEST_DIR/themes" .

# Create valid theme.properties but missing templates
cat > themes/obp/theme.properties << 'EOF'
parent=base
styles=css/styles.css
EOF

mkdir -p themes/obp/login
# Only create login.ftl, missing template.ftl
cat > themes/obp/login/login.ftl << 'EOF'
<#import "template.ftl" as layout>
</@layout.registrationLayout>
EOF

if validate_theme_files; then
    echo -e "${RED}✗ Test 4 FAILED (should have failed)${NC}"
    TEST4_RESULT="FAIL"
else
    echo -e "${GREEN}✓ Test 4 PASSED (correctly failed validation)${NC}"
    TEST4_RESULT="PASS"
fi
echo ""

# Test 5: No theme directory at all
echo -e "${CYAN}Test 5: No Theme Directory${NC}"
rm -rf themes

if validate_theme_files; then
    echo -e "${RED}✗ Test 5 FAILED (should have failed)${NC}"
    TEST5_RESULT="FAIL"
else
    echo -e "${GREEN}✓ Test 5 PASSED (correctly failed validation)${NC}"
    TEST5_RESULT="PASS"
fi
echo ""

# Test Summary
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}           Test Results Summary                 ${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

tests=("Complete Valid Theme" "Missing theme.properties" "Invalid theme.properties" "Missing Templates" "No Theme Directory")
results=($TEST1_RESULT $TEST2_RESULT $TEST3_RESULT $TEST4_RESULT $TEST5_RESULT)

passed=0
failed=0

for i in "${!tests[@]}"; do
    test_name="${tests[$i]}"
    result="${results[$i]}"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ Test $((i+1)): $test_name${NC}"
        ((passed++))
    else
        echo -e "${RED}✗ Test $((i+1)): $test_name${NC}"
        ((failed++))
    fi
done

echo ""
echo "Summary:"
echo "  Passed: $passed"
echo "  Failed: $failed"
echo "  Total:  ${#tests[@]}"

if [ $failed -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed! Theme validation is working correctly.${NC}"
    echo ""
    echo "The CI/CD script will properly:"
    echo "• Validate theme directory structure"
    echo "• Check required files exist"
    echo "• Verify theme.properties content"
    echo "• Ensure login templates are present"
    echo "• Report clear error messages for missing components"
else
    echo ""
    echo -e "${RED}❌ Some tests failed. Theme validation needs review.${NC}"
    echo ""
    echo "Check the validation logic in run-local-postgres-cicd.sh"
fi

echo ""
echo -e "${BLUE}Integration Test:${NC}"
echo "To test with actual deployment:"
echo "  ./sh/run-local-postgres-cicd.sh --themed"
echo ""
echo "To test validation only:"
echo "  ./sh/test-theme-validation.sh"
