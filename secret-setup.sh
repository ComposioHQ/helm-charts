#!/bin/bash

set -e  # Exit on first failure

# Colors for output
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

# Usage function
usage() {
    echo -e "${BLUE}Composio Secret Setup Script${NC}"
    echo ""
    echo "Sets up Kubernetes secrets for Composio deployment with auto-generated and user-provided secrets."
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 -r <release-name> -n <namespace> [options]"
    echo ""
    echo -e "${YELLOW}Required Parameters:${NC}"
    echo "  -r, --release     Release name (used for secret naming: \${release}-secret-type)"
    echo "  -n, --namespace   Kubernetes namespace"
    echo ""
    echo -e "${YELLOW}Optional Parameters:${NC}"
    echo "  -d, --dry-run       Show what would be done without making actual changes"
    echo "  --skip-generated    Skip creating auto-generated secrets, only create user-provided ones"
    echo ""
    echo -e "${YELLOW}Optional Environment Variables stored in \${release}-composio-secrets:${NC}"
    echo "  POSTGRES_URL         PostgreSQL connection URL for Apollo (postgresql://user:pass@host:port/db)"
    echo "  THERMOS_POSTGRES_URL PostgreSQL connection URL for Thermos (postgresql://user:pass@host:port/db)"
    echo "  REDIS_URL            Redis connection URL (redis://user:pass@host:port/db)"
    echo "  OPENAI_API_KEY       OpenAI API key for AI functionality"
    echo "  AZURE_CONNECTION_STRING Azure Storage connection string for Apollo (when backend=azure)"
    echo "  S3_ACCESS_KEY_ID     S3 access key ID used by Apollo"
    echo "  S3_SECRET_ACCESS_KEY S3 secret access key used by Apollo"
    echo "  SMTP_CONNECTION_STRING SMTP connection string (e.g., smtps://user:pass@smtp.example.com:465)"
    echo "  SMTP_SECRET_NAME     Optional. Overrides default secret name (\${release}-smtp-credentials)"
    echo ""
    echo -e "${YELLOW}Generated Secrets (auto-created if missing):${NC}"
    echo "  • \${release}-composio-secrets (contains COMPOSIO_ADMIN_TOKEN, ENCRYPTION_KEY, TEMPORAL_TRIGGER_ENCRYPTION_KEY, JWT_SECRET, and optional user-provided URLs/keys)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # Setup with all external secrets"
    echo "  POSTGRES_URL=\"postgresql://user:pass@apollo-db.example.com:5432/apollo\" \\"
    echo "  THERMOS_POSTGRES_URL=\"postgresql://user:pass@thermos-db.example.com:5432/thermos\" \\"
    echo "  REDIS_URL=\"redis://user:pass@redis.example.com:6379/0\" \\"
    echo "  OPENAI_API_KEY=\"sk-1234567890abcdef...\" \\"
    echo "  $0 -r composio -n composio"
    echo ""
    echo "  # Dry-run to see what would be created"
    echo "  $0 -r composio -n composio --dry-run"
    echo ""
}

# Parse command line arguments
RELEASE_NAME=""
NAMESPACE=""
DRY_RUN=false
SKIP_GENERATED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-generated)
            SKIP_GENERATED=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RELEASE_NAME" ]] || [[ -z "$NAMESPACE" ]]; then
    print_error "Missing required parameters"
    usage
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    print_info "DRY-RUN MODE: Starting secret setup for release: $RELEASE_NAME in namespace: $NAMESPACE"
    print_warning "No actual changes will be made - showing commands that would be executed"
else
    print_info "Starting secret setup for release: $RELEASE_NAME in namespace: $NAMESPACE"
fi

# Function to check if namespace exists
namespace_exists() {
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1
}

# Create namespace if it doesn't exist
if namespace_exists; then
    print_info "Namespace already exists: $NAMESPACE"
else
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create namespace: $NAMESPACE"
        print_info "kubectl create namespace \"$NAMESPACE\""
    else
        print_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
        print_success "Created namespace: $NAMESPACE"
    fi
fi

# Function to generate random string
generate_random() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Function to check if secret exists
secret_exists() {
    local secret_name=$1
    kubectl get secret "$secret_name" -n "$NAMESPACE" >/dev/null 2>&1
}

# Function to fetch and decode an existing secret value (returns empty string if missing)
get_secret_value() {
    local secret_name=$1
    local key=$2
    kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath="{.data.$key}" 2>/dev/null | base64 --decode 2>/dev/null || true
}

# Function to create secret with single key-value
create_simple_secret() {
    local secret_name=$1
    local key=$2
    local value=$3
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"$key=$value\" -n \"$NAMESPACE\""
    else
        print_info "Creating secret: $secret_name"
        kubectl create secret generic "$secret_name" \
            --from-literal="$key=$value" \
            -n "$NAMESPACE"
        print_success "Created secret: $secret_name"
    fi
}


# Function to create S3 credentials secret (used by apollo.yaml)
create_s3_secret() {
    local secret_name=$1
    local access_key=$2
    local secret_key=$3
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"S3_ACCESS_KEY_ID=$access_key\" --from-literal=\"S3_SECRET_ACCESS_KEY=$secret_key\" -n \"$NAMESPACE\""
    else
        print_info "Creating secret: $secret_name"
        kubectl create secret generic "$secret_name" \
            --from-literal="S3_ACCESS_KEY_ID=$access_key" \
            --from-literal="S3_SECRET_ACCESS_KEY=$secret_key" \
            -n "$NAMESPACE"
        print_success "Created secret: $secret_name"
    fi
}

CORE_SECRET_NAME="${RELEASE_NAME}-composio-secrets"

if [[ "$SKIP_GENERATED" == true ]]; then
    print_info "Skipping generated secrets due to --skip-generated flag"
else
    print_info "Checking and creating generated secrets..."

    if secret_exists "$CORE_SECRET_NAME"; then
        print_warning "Secret already exists: $CORE_SECRET_NAME"
        patch_fields=()
        [[ -n "$POSTGRES_URL" ]] && patch_fields+=("\"POSTGRES_URL\":\"$POSTGRES_URL\"")
        [[ -n "$THERMOS_POSTGRES_URL" ]] && patch_fields+=("\"THERMOS_DATABASE_URL\":\"$THERMOS_POSTGRES_URL\"")
        [[ -n "$REDIS_URL" ]] && patch_fields+=("\"REDIS_URL\":\"$REDIS_URL\"")
        [[ -n "$OPENAI_API_KEY" ]] && patch_fields+=("\"OPENAI_API_KEY\":\"$OPENAI_API_KEY\"")

        if [[ ${#patch_fields[@]} -gt 0 ]]; then
            patch_json="{\"stringData\":{${patch_fields[*]}}}"
            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY-RUN] Would patch $CORE_SECRET_NAME with: $patch_json"
            else
                print_info "Patching $CORE_SECRET_NAME with provided connection values"
                kubectl patch secret "$CORE_SECRET_NAME" -n "$NAMESPACE" -p "$patch_json"
                print_success "Patched $CORE_SECRET_NAME"
            fi
        fi
    else
        print_info "Creating consolidated core secret: $CORE_SECRET_NAME"

        apollo_admin_token="$(get_secret_value "${RELEASE_NAME}-composio-admin-token" "COMPOSIO_ADMIN_TOKEN")"
        encryption_key="$(get_secret_value "${RELEASE_NAME}-encryption-key" "ENCRYPTION_KEY")"
        temporal_encryption_key="$(get_secret_value "${RELEASE_NAME}-temporal-encryption-key" "TEMPORAL_TRIGGER_ENCRYPTION_KEY")"
        jwt_secret="$(get_secret_value "${RELEASE_NAME}-jwt-secret" "JWT_SECRET")"

        [[ -z "$apollo_admin_token" ]] && apollo_admin_token="$(generate_random 32)"
        [[ -z "$encryption_key" ]] && encryption_key="$(generate_random 32)"
        [[ -z "$temporal_encryption_key" ]] && temporal_encryption_key="$(generate_random 32)"
        [[ -z "$jwt_secret" ]] && jwt_secret="$(generate_random 32)"

        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would create secret: $CORE_SECRET_NAME"
            print_info "kubectl create secret generic \"$CORE_SECRET_NAME\" \\"
            print_info "  --from-literal=\"COMPOSIO_ADMIN_TOKEN=$apollo_admin_token\" \\"
            print_info "  --from-literal=\"ENCRYPTION_KEY=$encryption_key\" \\"
            print_info "  --from-literal=\"TEMPORAL_TRIGGER_ENCRYPTION_KEY=$temporal_encryption_key\" \\"
            print_info "  --from-literal=\"JWT_SECRET=$jwt_secret\" \\"
            [[ -n "$POSTGRES_URL" ]] && print_info "  --from-literal=\"POSTGRES_URL=$POSTGRES_URL\" \\"
            [[ -n "$THERMOS_POSTGRES_URL" ]] && print_info "  --from-literal=\"THERMOS_DATABASE_URL=$THERMOS_POSTGRES_URL\" \\"
            [[ -n "$REDIS_URL" ]] && print_info "  --from-literal=\"REDIS_URL=$REDIS_URL\" \\"
            [[ -n "$OPENAI_API_KEY" ]] && print_info "  --from-literal=\"OPENAI_API_KEY=$OPENAI_API_KEY\" \\"
            print_info "  -n \"$NAMESPACE\""
        else
            create_args=(
                kubectl create secret generic "$CORE_SECRET_NAME"
                --from-literal="COMPOSIO_ADMIN_TOKEN=$apollo_admin_token"
                --from-literal="ENCRYPTION_KEY=$encryption_key"
                --from-literal="TEMPORAL_TRIGGER_ENCRYPTION_KEY=$temporal_encryption_key"
                --from-literal="JWT_SECRET=$jwt_secret"
                -n "$NAMESPACE"
            )
            [[ -n "$POSTGRES_URL" ]] && create_args+=(--from-literal="POSTGRES_URL=$POSTGRES_URL")
            [[ -n "$THERMOS_POSTGRES_URL" ]] && create_args+=(--from-literal="THERMOS_DATABASE_URL=$THERMOS_POSTGRES_URL")
            [[ -n "$REDIS_URL" ]] && create_args+=(--from-literal="REDIS_URL=$REDIS_URL")
            [[ -n "$OPENAI_API_KEY" ]] && create_args+=(--from-literal="OPENAI_API_KEY=$OPENAI_API_KEY")

            "${create_args[@]}"

            print_success "Created secret: $CORE_SECRET_NAME"
        fi
    fi

fi

# Azure connection string secret (used by apollo.yaml when backend=azure)
if [[ -n "$AZURE_CONNECTION_STRING" ]]; then
    azure_secret_name="${RELEASE_NAME}-azure-connection-string"
    if secret_exists "$azure_secret_name"; then
        print_warning "Secret already exists: $azure_secret_name"
    else
        create_simple_secret "$azure_secret_name" "AZURE_CONNECTION_STRING" "$AZURE_CONNECTION_STRING"
    fi
else
    print_info "AZURE_CONNECTION_STRING not provided - skipping Azure connection secret creation"
fi

# S3 credentials secret (required by apollo.yaml env valueFrom)
if [[ -n "$S3_ACCESS_KEY_ID" && -n "$S3_SECRET_ACCESS_KEY" ]]; then
    s3_secret_name="${RELEASE_NAME}-s3-credentials"
    if secret_exists "$s3_secret_name"; then
        print_warning "Secret already exists: $s3_secret_name"
    else
        create_s3_secret "$s3_secret_name" "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY"
    fi
else
    print_info "S3_ACCESS_KEY_ID or S3_SECRET_ACCESS_KEY not provided - skipping S3 credentials secret creation"
fi

# SMTP secret from environment variable (for apollo.yaml reference at runtime)
if [[ -n "$SMTP_CONNECTION_STRING" ]]; then
    smtp_secret_name="${SMTP_SECRET_NAME:-${RELEASE_NAME}-smtp-credentials}"
    if secret_exists "$smtp_secret_name"; then
        print_warning "Secret already exists: $smtp_secret_name"
    else
        create_simple_secret "$smtp_secret_name" "SMTP_CONNECTION_STRING" "$SMTP_CONNECTION_STRING"
    fi
else
    print_info "SMTP_CONNECTION_STRING not provided - skipping SMTP secret creation"
fi

if [[ "$DRY_RUN" == true ]]; then
    print_success "Dry-run completed successfully!"
    print_info "No actual changes were made. The commands above show what would be executed."
else
    print_success "Secret setup completed successfully!"
    
    print_info "Summary of secrets in namespace '$NAMESPACE':"
    kubectl get secrets -n "$NAMESPACE" | grep -E "($RELEASE_NAME)" || print_warning "No matching secrets found"
fi

print_info "To view a specific secret:"
print_info "kubectl get secret <secret-name> -n $NAMESPACE -o yaml"

print_info "To get a decoded secret value:"
print_info "kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data.<key>}' | base64 -d" 
