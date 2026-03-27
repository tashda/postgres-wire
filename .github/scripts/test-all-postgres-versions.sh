#!/bin/bash

# test-all-postgres-versions.sh
# Runs PostgresKit integration tests against multiple PostgreSQL versions using Docker.

VERSIONS=("14" "15" "16" "17" "18" "latest")
EXIT_CODE=0

echo "🧪 Starting multi-version Postgres integration tests..."

for VERSION in "${VERSIONS[@]}"
do
    echo ""
    echo "--------------------------------------------------------"
    echo "🐘 Testing against PostgreSQL version: $VERSION"
    echo "--------------------------------------------------------"
    
    # Export environment variables for the Swift test suite
    export USE_DOCKER=1
    export POSTGRES_VERSION=$VERSION
    # Use a different port to avoid conflicts
    export POSTGRES_PORT=54321
    
    # Run only the PostgresKitTests target
    swift test --filter PostgresKitTests
    
    CURRENT_EXIT_CODE=$?
    if [ $CURRENT_EXIT_CODE -ne 0 ]; then
        echo "❌ Tests failed for PostgreSQL version $VERSION"
        EXIT_CODE=$CURRENT_EXIT_CODE
    else
        echo "✅ Tests passed for PostgreSQL version $VERSION"
    fi
done

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "🎉 All versions passed!"
else
    echo "💥 Some versions failed. Check the logs above."
fi

exit $EXIT_CODE
