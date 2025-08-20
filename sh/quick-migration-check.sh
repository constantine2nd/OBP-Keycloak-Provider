#!/bin/bash

# Quick Migration Status Check Script
# This script quickly diagnoses the current migration status and provides actionable steps

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONTAINER_NAME="obp-keycloak-local"
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="obp"
DB_NAME="obp_mapped"

echo -e "${BLUE}🔍 QUICK MIGRATION STATUS CHECK${NC}"
echo "================================="

# Step 1: Check if container is running
echo -n "1. Container status: "
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
    echo "   Start with: ./sh/run-local-postgres.sh --themed --validate"
    exit 1
fi

# Step 2: Check database connectivity
echo -n "2. Database connectivity: "
if PGPASSWORD="f" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
    echo -e "${GREEN}✅ Connected${NC}"
else
    echo -e "${RED}❌ Failed${NC}"
    echo "   Check: PGPASSWORD=f psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
    exit 1
fi

# Step 3: Check users with uniqueid
echo -n "3. Users needing migration: "
uniqueid_count=$(PGPASSWORD="f" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT COUNT(*) FROM authuser WHERE uniqueid IS NOT NULL AND uniqueid != '';" 2>/dev/null | tr -d ' ')
if [ "$uniqueid_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $uniqueid_count users${NC}"
else
    echo -e "${GREEN}✅ 0 users (all migrated)${NC}"
fi

# Step 4: Check if migration code is active
echo -n "4. Migration code status: "
if docker logs "$CONTAINER_NAME" 2>/dev/null | grep -q "MIGRATION CHECK"; then
    echo -e "${GREEN}✅ Active${NC}"
else
    echo -e "${RED}❌ Not detected${NC}"
    echo "   Need to rebuild: mvn clean package && restart container"
fi

# Step 5: Check migration activity
echo -n "5. Migration activity: "
migration_count=$(docker logs "$CONTAINER_NAME" 2>/dev/null | grep -c "MIGRATION SUCCESS" || true)
migration_count=${migration_count:-0}
if [ "$migration_count" -gt 0 ]; then
    echo -e "${GREEN}✅ $migration_count migrations completed${NC}"
else
    echo -e "${YELLOW}⚠️  No migrations yet${NC}"
fi

# Step 6: Check optimal lookups
echo -n "6. Optimal performance: "
optimal_count=$(docker logs "$CONTAINER_NAME" 2>/dev/null | grep -c "OPTIMAL LOOKUP" || true)
optimal_count=${optimal_count:-0}
if [ "$optimal_count" -gt 0 ]; then
    echo -e "${GREEN}✅ $optimal_count optimal lookups${NC}"
else
    echo -e "${YELLOW}⚠️  No optimal lookups yet${NC}"
fi

echo ""
echo -e "${CYAN}📊 SUMMARY${NC}"
echo "=========="

# Determine status and recommendations
if [ "$uniqueid_count" -eq 0 ]; then
    echo -e "${GREEN}🎉 MIGRATION COMPLETE: All users are already migrated${NC}"
elif docker logs "$CONTAINER_NAME" 2>/dev/null | grep -q "MIGRATION CHECK"; then
    echo -e "${YELLOW}🔄 MIGRATION READY: Updated code deployed, migration will happen on user login${NC}"
    echo ""
    echo -e "${CYAN}📋 NEXT STEPS:${NC}"
    echo "1. Test user authentication to trigger migration"
    echo "2. Or force migration: docker restart $CONTAINER_NAME"
    echo "3. Monitor: docker logs $CONTAINER_NAME -f | grep MIGRATION"
else
    echo -e "${RED}🔧 MIGRATION NEEDED: Deploy updated code first${NC}"
    echo ""
    echo -e "${CYAN}📋 NEXT STEPS:${NC}"
    echo "1. Build updated code: mvn clean package -DskipTests"
    echo "2. Stop container: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
    echo "3. Restart: ./sh/run-local-postgres.sh --themed --validate --build"
    echo "4. Check again: ./sh/quick-migration-check.sh"
fi

echo ""
echo -e "${CYAN}🔗 USEFUL COMMANDS:${NC}"
echo "Monitor logs: docker logs $CONTAINER_NAME -f"
echo "Check database: PGPASSWORD=f psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
echo "Admin console: https://localhost:8443/admin"

if [ "$uniqueid_count" -gt 0 ]; then
    echo ""
    echo -e "${CYAN}👥 USERS NEEDING MIGRATION:${NC}"
    PGPASSWORD="f" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT id, username, LEFT(uniqueid, 20) || '...' as uniqueid_preview FROM authuser WHERE uniqueid IS NOT NULL AND uniqueid != '' ORDER BY username LIMIT 5;" 2>/dev/null

    if [ "$uniqueid_count" -gt 5 ]; then
        echo "... and $((uniqueid_count - 5)) more users"
    fi
fi

echo ""
echo -e "${BLUE}Run './sh/migrate-local-uniqueid.sh' for interactive migration help${NC}"
