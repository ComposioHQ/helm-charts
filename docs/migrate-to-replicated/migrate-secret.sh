#!/bin/bash

# Script to create composio-composio-secrets from existing secrets
# Usage: ./create-composio-secret.sh -r <release-name> -n <namespace>

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to display usage
usage() {
    echo -e "${BLUE}Composio Combined Secret Creation Script${NC}"
    echo ""
    echo "Creates composio-composio-secrets from existing individual secrets."
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 -r <release-name> -n <namespace> [options]"
    echo ""
    echo -e "${YELLOW}Required Parameters:${NC}"
    echo "  -r, --release     Release name (prefix for source secret names)"
    echo "  -n, --namespace   Kubernetes namespace"
    echo ""
    echo -e "${YELLOW}Optional Parameters:${NC}"
    echo "  -f, --force       Force recreate if secret already exists (no prompt)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo -e "${YELLOW}Source Secrets (must exist):${NC}"
    echo "  • \${release}-apollo-admin-token"
    echo "  • \${release}-encryption-key"
    echo "  • \${release}-temporal-encryption-key"
    echo "  • \${release}-jwt-secret"
    echo "  • external-postgres-secret"
    echo "  • external-thermos-postgres-secret"
    echo "  • external-redis-secret"
    echo ""
    echo -e "${YELLOW}Output Secret:${NC}"
    echo "  • composio-composio-secrets (fixed name, no prefix)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 -r composio -n composio"
    echo "  $0 -r my-app -n production --force"
    echo ""
    exit 1
}

# Function to get secret value
get_secret_value() {
    local secret_name=$1
    local key=$2
    local namespace=$3
    
    local value
    value=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d)
    
    if [ -z "$value" ]; then
        print_error "Failed to extract key '$key' from secret '$secret_name'"
        return 1
    fi
    
    echo "$value"
}

# Function to check if secret exists
check_secret_exists() {
    local secret_name=$1
    local namespace=$2
    
    if ! kubectl get secret "$secret_name" -n "$namespace" &>/dev/null; then
        print_error "Secret '$secret_name' not found in namespace '$namespace'"
        return 1
    fi
    return 0
}

# Parse command line arguments
RELEASE_NAME=""
NAMESPACE=""
FORCE=false

while [ $# -gt 0 ]; do
    case $1 in
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$RELEASE_NAME" ] || [ -z "$NAMESPACE" ]; then
    print_error "Both release name and namespace are required"
    usage
fi

print_info "Creating composio-composio-secrets in namespace: $NAMESPACE"
print_info "Using release name: $RELEASE_NAME (for source secret prefixes)"
echo ""

# Define secret names with release prefix
APOLLO_ADMIN_SECRET="${RELEASE_NAME}-apollo-admin-token"
ENCRYPTION_SECRET="${RELEASE_NAME}-encryption-key"
TEMPORAL_ENCRYPTION_SECRET="${RELEASE_NAME}-temporal-encryption-key"
JWT_SECRET_NAME="${RELEASE_NAME}-jwt-secret"

# Check if all required secrets exist
print_info "Checking if required secrets exist..."
REQUIRED_SECRETS=(
    "$APOLLO_ADMIN_SECRET"
    "$ENCRYPTION_SECRET"
    "$TEMPORAL_ENCRYPTION_SECRET"
    "$JWT_SECRET_NAME"
    "external-postgres-secret"
    "external-thermos-postgres-secret"
    "external-redis-secret"
)

MISSING_SECRETS=()
for secret in "${REQUIRED_SECRETS[@]}"; do
    if check_secret_exists "$secret" "$NAMESPACE"; then
        print_success "✓ $secret found"
    else
        MISSING_SECRETS+=("$secret")
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    print_error "Missing required secrets:"
    for secret in "${MISSING_SECRETS[@]}"; do
        echo "  - $secret"
    done
    echo ""
    print_info "Please create the missing secrets first using the setup script or manually."
    exit 1
fi

echo ""
print_info "Extracting values from secrets..."

# Extract values from secrets
APOLLO_ADMIN_TOKEN=$(get_secret_value "$APOLLO_ADMIN_SECRET" "APOLLO_ADMIN_TOKEN" "$NAMESPACE")
ENCRYPTION_KEY=$(get_secret_value "$ENCRYPTION_SECRET" "ENCRYPTION_KEY" "$NAMESPACE")
TEMPORAL_TRIGGER_ENCRYPTION_KEY=$(get_secret_value "$TEMPORAL_ENCRYPTION_SECRET" "TEMPORAL_TRIGGER_ENCRYPTION_KEY" "$NAMESPACE")
JWT_SECRET=$(get_secret_value "$JWT_SECRET_NAME" "JWT_SECRET" "$NAMESPACE")
POSTGRES_URL=$(get_secret_value "external-postgres-secret" "url" "$NAMESPACE")
POSTGRES_PASSWORD=$(get_secret_value "external-postgres-secret" "password" "$NAMESPACE")
THERMOS_DATABASE_URL=$(get_secret_value "external-thermos-postgres-secret" "url" "$NAMESPACE")
REDIS_URL=$(get_secret_value "external-redis-secret" "url" "$NAMESPACE")


# Validate that we got all values
if [ -z "$APOLLO_ADMIN_TOKEN" ] || [ -z "$ENCRYPTION_KEY" ] || [ -z "$TEMPORAL_TRIGGER_ENCRYPTION_KEY" ] || \
   [ -z "$JWT_SECRET" ] || [ -z "$POSTGRES_URL" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$THERMOS_DATABASE_URL" ] || [ -z "$REDIS_URL" ]; then
    print_error "Failed to extract one or more required values from secrets"
    exit 1
fi

print_success "✓ All values extracted successfully"
echo ""

# Target secret name (fixed name, no prefix)
TARGET_SECRET="composio-composio-secrets"

# Check if the target secret already exists
if kubectl get secret "$TARGET_SECRET" -n "$NAMESPACE" &>/dev/null; then
    if [ "$FORCE" = true ]; then
        print_warning "Secret '$TARGET_SECRET' already exists. Force flag set - deleting and recreating..."
        kubectl delete secret "$TARGET_SECRET" -n "$NAMESPACE"
        print_success "✓ Existing secret deleted"
    else
        print_warning "Secret '$TARGET_SECRET' already exists"
        read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete secret "$TARGET_SECRET" -n "$NAMESPACE"
            print_success "✓ Existing secret deleted"
        else
            print_info "Aborted. Use --force flag to skip this prompt."
            exit 0
        fi
    fi
fi

print_info "Creating secret $TARGET_SECRET..."

# Create the combined secret
kubectl create secret generic "$TARGET_SECRET" \
  --from-literal=COMPOSIO_ADMIN_TOKEN="$APOLLO_ADMIN_TOKEN" \
  --from-literal=ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY="$TEMPORAL_TRIGGER_ENCRYPTION_KEY" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=POSTGRES_URL="$POSTGRES_URL" \
  --from-literal=THERMOS_DATABASE_URL="$THERMOS_DATABASE_URL" \
  --from-literal=password="$POSTGRES_PASSWORD" \
  --from-literal=REDIS_URL="$REDIS_URL" \
  -n "$NAMESPACE"

if [ $? -eq 0 ]; then
    print_success "✓ Secret '$TARGET_SECRET' created successfully in namespace '$NAMESPACE'"
    echo ""
    print_info "Secret contains the following keys:"
    echo "  • COMPOSIO_ADMIN_TOKEN"
    echo "  • ENCRYPTION_KEY"
    echo "  • TEMPORAL_TRIGGER_ENCRYPTION_KEY"
    echo "  • JWT_SECRET"
    echo "  • POSTGRES_URL"
    echo "  • THERMOS_DATABASE_URL"
    echo "  • password"
    echo ""
    print_info "To view the secret:"
    print_info "  kubectl get secret $TARGET_SECRET -n $NAMESPACE -o yaml"
    echo ""
    print_info "To decode a specific value:"
    print_info "  kubectl get secret $TARGET_SECRET -n $NAMESPACE -o jsonpath='{.data.POSTGRES_URL}' | base64 -d"
else
    print_error "Failed to create secret"
    exit 1
fi
