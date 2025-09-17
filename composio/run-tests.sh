#!/bin/bash

# Helm Unit Test Runner for Composio Chart
# This script runs all unit tests using helm unittest plugin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_status $BLUE "🧪 Composio Helm Chart Unit Test Runner"
print_status $BLUE "======================================"

# Check if helm unittest plugin is installed
if ! helm unittest --help > /dev/null 2>&1; then
    print_status $RED "❌ helm unittest plugin is not installed"
    print_status $YELLOW "📦 Installing helm unittest plugin..."
    helm plugin install https://github.com/helm-unittest/helm-unittest.git
    if [ $? -eq 0 ]; then
        print_status $GREEN "✅ helm unittest plugin installed successfully"
    else
        print_status $RED "❌ Failed to install helm unittest plugin"
        exit 1
    fi
fi

# Navigate to chart directory
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CHART_DIR"

print_status $BLUE "📂 Chart directory: $CHART_DIR"

# Check if tests directory exists
if [ ! -d "tests" ]; then
    print_status $RED "❌ Tests directory not found"
    exit 1
fi

# Count test files
TEST_COUNT=$(find tests -name "*_test.yaml" | wc -l)
print_status $BLUE "🔍 Found $TEST_COUNT test files"

# Run tests with different options based on arguments
case "${1:-all}" in
    "all")
        print_status $YELLOW "🚀 Running all tests..."
        helm unittest . -f 'tests/*_test.yaml' --color
        ;;
    "apollo")
        print_status $YELLOW "🚀 Running Apollo tests..."
        helm unittest . -f 'tests/apollo_test.yaml' --color
        ;;
    "mercury")
        print_status $YELLOW "🚀 Running Mercury tests..."
        helm unittest . -f 'tests/mercury_test.yaml' --color
        ;;

    "thermos")
        print_status $YELLOW "🚀 Running Thermos tests..."
        helm unittest . -f 'tests/thermos_test.yaml' --color
        ;;
    "minio")
        print_status $YELLOW "🚀 Running Minio tests..."
        helm unittest . -f 'tests/minio_test.yaml' --color
        ;;
    "knative")
        print_status $YELLOW "🚀 Running Knative tests..."
        helm unittest . -f 'tests/knative_test.yaml' --color
        ;;
    "helpers")
        print_status $YELLOW "🚀 Running Helper function tests..."
        helm unittest . -f 'tests/helpers_test.yaml' --color
        ;;
    "secrets")
        print_status $YELLOW "🚀 Running Secrets tests..."
        helm unittest . -f 'tests/ecr_secret_test.yaml' --color
        ;;
    "db")
        print_status $YELLOW "🚀 Running Database Init tests..."
        helm unittest . -f 'tests/db_init_test.yaml' --color
        ;;
    "ingress")
        print_status $YELLOW "🚀 Running Ingress tests..."
        helm unittest . -f 'tests/ingress_test.yaml' --color
        ;;
    "verbose")
        print_status $YELLOW "🚀 Running all tests in verbose mode..."
        helm unittest . -f 'tests/*_test.yaml' --color -v
        ;;
    "debug")
        print_status $YELLOW "🔍 Running tests in debug mode..."
        helm unittest . -f 'tests/*_test.yaml' --color -v --debug
        ;;
    "with-subchart")
        print_status $YELLOW "🚀 Running tests including subcharts..."
        helm unittest . -f 'tests/*_test.yaml' --color --with-subchart
        ;;
    *)
        print_status $RED "❌ Unknown test target: $1"
        print_status $YELLOW "Available options:"
        echo "  all         - Run all tests (default)"
        echo "  apollo      - Run Apollo service tests"
        echo "  mercury     - Run Mercury service tests"

        echo "  thermos     - Run Thermos service tests"
        echo "  minio       - Run Minio tests"
        echo "  knative     - Run Knative tests"
        echo "  helpers     - Run helper function tests"
        echo "  secrets     - Run secrets tests"
        echo "  db          - Run database init tests"
        echo "  ingress     - Run ingress tests"
        echo "  verbose     - Run all tests with verbose output"
        echo "  debug       - Run tests with debug output"
        echo "  with-subchart - Run tests including subcharts"
        exit 1
        ;;
esac

# Check exit code
if [ $? -eq 0 ]; then
    print_status $GREEN "✅ All tests passed successfully!"
else
    print_status $RED "❌ Some tests failed"
    exit 1
fi 