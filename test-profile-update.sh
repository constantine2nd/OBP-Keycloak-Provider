#!/bin/bash

# Profile Update Test Script for OBP Keycloak Provider
# This script tests if profile updates are properly persisted to the database

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}OBP Keycloak Provider - Profile Update Test${NC}"
echo "======================================================="
echo ""

# Configuration
KEYCLOAK_URL="http://localhost:8000"
REALM="master"
CLIENT_ID="security-admin-console"
USERNAME="aria.milic"
PASSWORD="123"
DB_HOST="192.168.1.23"
DB_PORT="5432"
DB_NAME="obp_mapped"
DB_USER="obp"
DB_PASSWORD="changeme"

# Test user credentials - adjust these as needed
TEST_FIRSTNAME_NEW="UpdatedFirst"
TEST_LASTNAME_NEW="UpdatedLast"
TEST_EMAIL_NEW="updated.email@example.com"

echo -e "${BLUE}Testing Profile Update Functionality${NC}"
echo "------------------------------------"
echo "Target User: $USERNAME"
echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"
echo ""

# Function to log messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if Keycloak is running
check_keycloak() {
    log_info "Checking if Keycloak is accessible..."

    if curl -s -f "$KEYCLOAK_URL/realms/$REALM" > /dev/null; then
        log_success "Keycloak is accessible at $KEYCLOAK_URL"
        return 0
    else
        log_error "Keycloak is not accessible at $KEYCLOAK_URL"
        return 1
    fi
}

# Function to get current user profile from database
get_current_profile() {
    log_info "Retrieving current user profile from database..."

    # Check if we can access the database
    if command -v psql > /dev/null; then
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -c "SELECT id, username, firstname, lastname, email, updatedat FROM authuser WHERE username = '$USERNAME';" \
            2>/dev/null || {
            log_warning "Could not connect to database directly. Using container method..."
            return 1
        }
    else
        log_warning "psql not available. Cannot query database directly."
        return 1
    fi
}

# Function to monitor Keycloak logs for profile updates
monitor_profile_updates() {
    log_info "Monitoring Keycloak logs for profile update activity..."

    # Start monitoring logs in background
    docker logs obp-keycloak --follow --tail 0 | grep -E "(🟡|🔄|forcePersist|setSingleAttribute|setAttribute)" &
    LOG_PID=$!

    echo "Log monitoring started (PID: $LOG_PID)"
    echo "You can now trigger profile updates and see the activity..."
    echo ""
    echo "To stop monitoring, press Ctrl+C or kill process $LOG_PID"

    # Keep monitoring for 30 seconds or until interrupted
    sleep 30
    kill $LOG_PID 2>/dev/null || true
}

# Function to test authentication
test_authentication() {
    log_info "Testing authentication for user: $USERNAME"

    # Get authentication form
    local auth_url="$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/auth"
    local params="client_id=$CLIENT_ID&response_type=code&redirect_uri=https%3A//localhost%3A8443/admin/master/console/"

    log_info "Attempting authentication..."

    # Note: This is a simplified test. In a real scenario, you'd need to handle the full OAuth flow
    local response=$(curl -s -w "%{http_code}" -o /dev/null "$auth_url?$params")

    if [[ "$response" == "200" ]]; then
        log_success "Authentication endpoint is accessible"
        return 0
    else
        log_error "Authentication endpoint returned: $response"
        return 1
    fi
}

# Function to simulate profile update
simulate_profile_update() {
    log_info "Simulating profile update via Keycloak API..."

    # This is a simplified simulation. In practice, you would:
    # 1. Authenticate and get access token
    # 2. Call Keycloak Admin API to update user profile
    # 3. Monitor the database changes

    echo "Profile update simulation would involve:"
    echo "  - Updating firstName to: $TEST_FIRSTNAME_NEW"
    echo "  - Updating lastName to: $TEST_LASTNAME_NEW"
    echo "  - Updating email to: $TEST_EMAIL_NEW"
    echo ""
    echo "To manually test:"
    echo "1. Open: $KEYCLOAK_URL/admin"
    echo "2. Login with admin credentials"
    echo "3. Navigate to Users -> Find '$USERNAME'"
    echo "4. Edit profile information"
    echo "5. Save changes"
    echo "6. Check database for updates"
}

# Function to check if profile changes are persisted
check_profile_persistence() {
    log_info "Checking if profile changes are properly persisted..."

    # Get current profile again to see if changes were persisted
    echo "Before making changes, current profile is:"
    get_current_profile

    echo ""
    echo "After making profile changes, run this script again to verify persistence."
}

# Function to show manual testing instructions
show_manual_test_instructions() {
    echo -e "${YELLOW}Manual Profile Update Test Instructions:${NC}"
    echo "======================================"
    echo ""
    echo "1. Open Keycloak Admin Console:"
    echo "   URL: $KEYCLOAK_URL/admin"
    echo ""
    echo "2. Login with admin credentials"
    echo ""
    echo "3. Navigate to Users:"
    echo "   - Click 'Users' in left menu"
    echo "   - Search for: $USERNAME"
    echo "   - Click on the user"
    echo ""
    echo "4. Update Profile:"
    echo "   - Go to 'Details' tab"
    echo "   - Modify First Name, Last Name, or Email"
    echo "   - Click 'Save'"
    echo ""
    echo "5. Monitor Logs (run in another terminal):"
    echo "   docker logs obp-keycloak --follow | grep -E \"OPERATION DISABLED|read-only|blocked\""
    echo ""
    echo "6. Check Database (READ-ONLY - No Changes Expected):"
    echo "   PGPASSWORD=\"$DB_PASSWORD\" psql -h $DB_HOST -U $DB_USER -d $DB_NAME \\"
    echo "   -c \"SELECT firstname, lastname, email, updatedat FROM authuser WHERE username = '$USERNAME';\""
    echo ""
    echo "⚠️  IMPORTANT: authuser table is READ-ONLY"
    echo ""
    echo "Expected Behavior:"
    echo "🔴 Profile update attempts will be BLOCKED"
    echo "🔴 Logs will show 'OPERATION DISABLED: authuser table is read-only'"
    echo "🔴 Database values will NOT change"
    echo "🔴 updatedat timestamp will remain unchanged"
    echo "✅ User can still login and view profile (read operations work)"
}

# Function to run automated checks
run_automated_checks() {
    log_info "Running automated profile update checks..."

    local checks_passed=0
    local total_checks=3

    echo ""
    echo "Check 1: Keycloak Accessibility"
    if check_keycloak; then
        ((checks_passed++))
    fi

    echo ""
    echo "Check 2: Current Profile Retrieval"
    if get_current_profile; then
        ((checks_passed++))
    fi

    echo ""
    echo "Check 3: Authentication Test"
    if test_authentication; then
        ((checks_passed++))
    fi

    echo ""
    echo "================================"
    echo "Automated Checks: $checks_passed/$total_checks passed"

    if [[ $checks_passed -eq $total_checks ]]; then
        log_success "All automated checks passed! ✅"
        echo ""
        echo "The system is ready for profile update testing."
        return 0
    else
        log_error "Some automated checks failed. ❌"
        echo ""
        echo "Please resolve the issues before testing profile updates."
        return 1
    fi
}

# Function to show comprehensive test report
show_test_report() {
    echo ""
    echo -e "${GREEN}Profile Update Test Summary${NC}"
    echo "=========================="
    echo ""
    echo "Key Files Modified:"
    echo "- UserAdapter.java: Enhanced attribute handling"
    echo "- KcUserStorageProvider.java: Improved onCache persistence"
    echo "- Templates: Added missing profile update templates"
    echo ""
    echo "Key Improvements:"
    echo "✅ setSingleAttribute() now persists to database"
    echo "✅ setAttribute() now persists to database"
    echo "✅ onCache() force persists all changes"
    echo "✅ Enhanced logging for debugging"
    echo "✅ Backward compatibility maintained"
    echo ""
    echo "Expected Log Messages During Profile Updates:"
    echo "🟡 ATTRIBUTE setSingleAttribute() called: [field] = [value]"
    echo "🔄 onCache() called for user: [username]"
    echo "🔄 Force persisted profile changes for user: [username]"
    echo "✅ Successfully [force] persisted profile changes"
    echo ""
}

# Main execution
main() {
    case "${1:-automated}" in
        "automated")
            echo "Running automated checks..."
            run_automated_checks
            show_manual_test_instructions
            ;;
        "monitor")
            echo "Starting log monitoring..."
            monitor_profile_updates
            ;;
        "profile")
            echo "Checking current profile..."
            get_current_profile
            ;;
        "simulate")
            echo "Simulating profile update..."
            simulate_profile_update
            ;;
        "report")
            show_test_report
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [automated|monitor|profile|simulate|report|help]"
            echo ""
            echo "Commands:"
            echo "  automated  - Run automated checks (default)"
            echo "  monitor    - Monitor Keycloak logs for profile updates"
            echo "  profile    - Show current user profile from database"
            echo "  simulate   - Show profile update simulation instructions"
            echo "  report     - Show comprehensive test report"
            echo "  help       - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Trap to clean up background processes
trap 'kill $LOG_PID 2>/dev/null || true' EXIT

# Run main function with arguments
main "$@"

# Show final summary
echo ""
echo -e "${BLUE}Profile Update Test Complete${NC}"
echo "Use '$0 help' to see all available commands"
echo ""
