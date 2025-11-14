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
    echo -e "${YELLOW}Optional Environment Variables for User-Provided Secrets:${NC}"
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
    echo "  • \${release}-apollo-admin-token      (APOLLO_ADMIN_TOKEN)"
    echo "  • \${release}-encryption-key          (ENCRYPTION_KEY)"
    echo "  • \${release}-temporal-encryption-key (TEMPORAL_TRIGGER_ENCRYPTION_KEY)"
    echo "  • \${release}-composio-api-key        (COMPOSIO_API_KEY)"
    echo "  • \${release}-jwt-secret              (JWT_SECRET)"
    echo "  • \${release}-minio-credentials       (MINIO_ROOT_USER + MINIO_ROOT_PASSWORD)"
    echo ""
    echo -e "${YELLOW}User-Provided Secrets (created if env vars provided):${NC}"
    echo "  • external-postgres-secret            (from POSTGRES_URL)"
    echo "  • external-thermos-postgres-secret    (from THERMOS_POSTGRES_URL)"
    echo "  • external-redis-secret               (from REDIS_URL)"
    echo "  • openai-secret                       (from OPENAI_API_KEY)"
    echo "  • \${release}-azure-connection-string (from AZURE_CONNECTION_STRING)"
    echo "  • \${release}-s3-credentials          (from S3_ACCESS_KEY_ID + S3_SECRET_ACCESS_KEY)"
    echo "  • \${release}-smtp-credentials        (from SMTP_CONNECTION_STRING)"
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

# Function to create minio credentials secret
create_minio_secret() {
    local secret_name=$1
    local user=$2
    local password=$3
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"MINIO_ROOT_USER=$user\" --from-literal=\"MINIO_ROOT_PASSWORD=$password\" -n \"$NAMESPACE\""
    else
        print_info "Creating secret: $secret_name"
        kubectl create secret generic "$secret_name" \
            --from-literal="MINIO_ROOT_USER=$user" \
            --from-literal="MINIO_ROOT_PASSWORD=$password" \
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

# Function to parse and create postgres secret
create_postgres_secret() {
    local url="$1"
    local secret_name="external-postgres-secret"
    
    print_info "Creating Apollo PostgreSQL secret from URL"
    
    # Parse URL to extract password
    local url_without_protocol=$(echo "$url" | sed -E 's|^[^:]+://||')
    local userpass_and_rest=$(echo "$url_without_protocol" | cut -d'@' -f1)
    local password=$(echo "$userpass_and_rest" | cut -d':' -f2)
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create Apollo PostgreSQL secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"url=$url\" --from-literal=\"password=$password\" -n \"$NAMESPACE\""
    else
        kubectl create secret generic "$secret_name" \
            --from-literal="url=$url" \
            --from-literal="password=$password" \
            -n "$NAMESPACE"
        
        print_success "Created Apollo PostgreSQL secret: $secret_name"
    fi
}

# Function to parse and create thermos postgres secret
create_thermos_postgres_secret() {
    local url="$1"
    local secret_name="external-thermos-postgres-secret"
    
    print_info "Creating Thermos PostgreSQL secret from URL"
    
    # Parse URL to extract password
    local url_without_protocol=$(echo "$url" | sed -E 's|^[^:]+://||')
    local userpass_and_rest=$(echo "$url_without_protocol" | cut -d'@' -f1)
    local password=$(echo "$userpass_and_rest" | cut -d':' -f2)
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create Thermos PostgreSQL secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"url=$url\" --from-literal=\"password=$password\" -n \"$NAMESPACE\""
    else
        kubectl create secret generic "$secret_name" \
            --from-literal="url=$url" \
            --from-literal="password=$password" \
            -n "$NAMESPACE"
        
        print_success "Created Thermos PostgreSQL secret: $secret_name"
    fi
}

# Function to parse and create redis secret  
create_redis_secret() {
    local url="$1"
    local secret_name="external-redis-secret"
    
    print_info "Creating Redis secret from URL"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create Redis secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"url=$url\" -n \"$NAMESPACE\""
    else
        kubectl create secret generic "$secret_name" \
            --from-literal="url=$url" \
            -n "$NAMESPACE"
        
        print_success "Created Redis secret: $secret_name"
    fi
}

# Function to create OpenAI secret
create_openai_secret() {
    local api_key="$1"
    local secret_name="openai-secret"
    
    print_info "Creating OpenAI secret"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create OpenAI secret: $secret_name"
        print_info "kubectl create secret generic \"$secret_name\" --from-literal=\"OPENAI_API_KEY=$api_key\" -n \"$NAMESPACE\""
    else
        kubectl create secret generic "$secret_name" \
            --from-literal="OPENAI_API_KEY=$api_key" \
            -n "$NAMESPACE"
        
        print_success "Created OpenAI secret: $secret_name"
    fi
}

if [[ "$SKIP_GENERATED" == true ]]; then
    print_info "Skipping generated secrets due to --skip-generated flag"
else
    print_info "Checking and creating generated secrets..."

    # Generated secrets - create separate secret objects
    GENERATED_SECRETS=(
        "${RELEASE_NAME}-apollo-admin-token:APOLLO_ADMIN_TOKEN"
        "${RELEASE_NAME}-encryption-key:ENCRYPTION_KEY" 
        "${RELEASE_NAME}-temporal-encryption-key:TEMPORAL_TRIGGER_ENCRYPTION_KEY"
        "${RELEASE_NAME}-composio-api-key:COMPOSIO_API_KEY"
        "${RELEASE_NAME}-jwt-secret:JWT_SECRET"
    )

    # Handle individual generated secrets
    for secret_def in "${GENERATED_SECRETS[@]}"; do
        secret_name=$(echo "$secret_def" | cut -d':' -f1)
        secret_key=$(echo "$secret_def" | cut -d':' -f2)
        
        if secret_exists "$secret_name"; then
            print_warning "Secret already exists: $secret_name"
        else
            secret_value=$(generate_random 32)
            create_simple_secret "$secret_name" "$secret_key" "$secret_value"
        fi
    done

    # Handle MinIO credentials (combined secret)
    minio_secret_name="${RELEASE_NAME}-minio-credentials"
    if secret_exists "$minio_secret_name"; then
        print_warning "Secret already exists: $minio_secret_name"
    else
        minio_user="minioadmin"
        minio_password=$(generate_random 16)
        create_minio_secret "$minio_secret_name" "$minio_user" "$minio_password"
    fi
fi

print_info "Checking and creating user-provided secrets..."

# Handle user-provided secrets from environment variables
if [[ -n "$POSTGRES_URL" ]]; then
    if secret_exists "external-postgres-secret"; then
        print_warning "Secret already exists: external-postgres-secret"
    else
        create_postgres_secret "$POSTGRES_URL"
    fi
else
    print_info "POSTGRES_URL not provided - skipping Apollo PostgreSQL secret creation"
fi

if [[ -n "$THERMOS_POSTGRES_URL" ]]; then
    if secret_exists "external-thermos-postgres-secret"; then
        print_warning "Secret already exists: external-thermos-postgres-secret"
    else
        create_thermos_postgres_secret "$THERMOS_POSTGRES_URL"
    fi
else
    print_info "THERMOS_POSTGRES_URL not provided - skipping Thermos PostgreSQL secret creation"
fi

if [[ -n "$REDIS_URL" ]]; then
    if secret_exists "external-redis-secret"; then
        print_warning "Secret already exists: external-redis-secret"  
    else
        create_redis_secret "$REDIS_URL"
    fi
else
    print_info "REDIS_URL not provided - skipping Redis secret creation"
fi

if [[ -n "$OPENAI_API_KEY" ]]; then
    if secret_exists "openai-secret"; then
        print_warning "Secret already exists: openai-secret"
    else
        create_openai_secret "$OPENAI_API_KEY"
    fi
else
    print_info "OPENAI_API_KEY not provided - skipping OpenAI secret creation"
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
    kubectl get secrets -n "$NAMESPACE" | grep -E "($RELEASE_NAME|external-|openai-)" || print_warning "No matching secrets found"
fi

print_info "To view a specific secret:"
print_info "kubectl get secret <secret-name> -n $NAMESPACE -o yaml"

print_info "To get a decoded secret value:"
print_info "kubectl get secret <secret-name> -n $NAMESPACE -o jsonpath='{.data.<key>}' | base64 -d" 