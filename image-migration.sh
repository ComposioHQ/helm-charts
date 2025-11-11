#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Composio Image Migration: ECR → GAR"
echo "=========================================="
echo ""

# Configuration
ECR_REGISTRY="008971668139.dkr.ecr.us-east-1.amazonaws.com"
GAR_REGISTRY="us-central1-docker.pkg.dev/infra-dev-464711/test-registry"
AWS_REGION="us-east-1"

# IMAGE TAG - Update this for new releases
IMAGE_TAG="${1:-release-2025_11_03}"

echo -e "${YELLOW}📦 Using image tag: $IMAGE_TAG${NC}"
echo ""

# Read AWS credentials from aws-credentials-secret.yaml
echo -e "${YELLOW}📋 Reading AWS credentials...${NC}"
AWS_ACCESS_KEY_ID=$(cat aws-credentials-secret.yaml | grep "AWS_ACCESS_KEY_ID" | sed 's/.*: "//;s/"$//')
AWS_SECRET_ACCESS_KEY=$(cat aws-credentials-secret.yaml | grep "AWS_SECRET_ACCESS_KEY" | sed 's/.*: "//;s/"$//')

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ Failed to read AWS credentials from aws-credentials-secret.yaml${NC}"
    exit 1
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$AWS_REGION

echo -e "${GREEN}✓ AWS credentials loaded${NC}"
echo ""

# Define images to migrate (as simple array)
IMAGES=(
    "apollo"
    "apollo-db-init"
    "thermos"
    "thermos-db-init"
    "mercury"
    "frontend"
)

# Authenticate to AWS ECR
echo -e "${YELLOW}🔐 Authenticating to AWS ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to authenticate to AWS ECR${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully authenticated to AWS ECR${NC}"
echo ""

# Authenticate to Google Artifact Registry
echo -e "${YELLOW}🔐 Authenticating to Google Artifact Registry...${NC}"
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to authenticate to GAR${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully authenticated to GAR${NC}"
echo ""

# Process each image
TOTAL=${#IMAGES[@]}
CURRENT=0
FAILED=()

for IMAGE_NAME in "${IMAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    
    echo "=========================================="
    echo -e "${YELLOW}[$CURRENT/$TOTAL] Processing: $IMAGE_NAME:$IMAGE_TAG${NC}"
    echo "=========================================="
    
    ECR_IMAGE="$ECR_REGISTRY/composio-self-host/$IMAGE_NAME:$IMAGE_TAG"
    GAR_IMAGE="$GAR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    
    # Pull from ECR (force AMD64 platform for compatibility with GKE)
    echo -e "${YELLOW}⬇️  Pulling from ECR (platform: linux/amd64)...${NC}"
    if docker pull --platform linux/amd64 $ECR_IMAGE; then
        echo -e "${GREEN}✓ Successfully pulled $ECR_IMAGE${NC}"
    else
        echo -e "${RED}❌ Failed to pull $ECR_IMAGE${NC}"
        FAILED+=("$IMAGE_NAME:$IMAGE_TAG")
        echo ""
        continue
    fi
    
    # Tag for GAR
    echo -e "${YELLOW}🏷️  Tagging for GAR...${NC}"
    if docker tag $ECR_IMAGE $GAR_IMAGE; then
        echo -e "${GREEN}✓ Successfully tagged as $GAR_IMAGE${NC}"
    else
        echo -e "${RED}❌ Failed to tag image${NC}"
        FAILED+=("$IMAGE_NAME:$IMAGE_TAG")
        echo ""
        continue
    fi
    
    # Push to GAR
    echo -e "${YELLOW}⬆️  Pushing to GAR...${NC}"
    if docker push $GAR_IMAGE; then
        echo -e "${GREEN}✓ Successfully pushed to GAR${NC}"
    else
        echo -e "${RED}❌ Failed to push to GAR${NC}"
        FAILED+=("$IMAGE_NAME:$IMAGE_TAG")
        echo ""
        continue
    fi
    
    # Clean up local images to save space
    echo -e "${YELLOW}🧹 Cleaning up local images...${NC}"
    docker rmi $ECR_IMAGE $GAR_IMAGE 2>/dev/null || true
    echo -e "${GREEN}✓ Local cleanup complete${NC}"
    echo ""
done

# Summary
echo "=========================================="
echo "Migration Summary"
echo "=========================================="
echo -e "Total images: $TOTAL"
echo -e "Successfully migrated: $((TOTAL - ${#FAILED[@]}))"
echo -e "Failed: ${#FAILED[@]}"

if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed images:${NC}"
    for FAILED_IMAGE in "${FAILED[@]}"; do
        echo -e "  - $FAILED_IMAGE"
    done
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ All images successfully migrated!${NC}"
    echo ""
    echo "Your images are now available at:"
    for IMAGE_NAME in "${IMAGES[@]}"; do
        echo "  - $GAR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    done
    echo ""
    echo "To use a different tag in the future, run:"
    echo "  ./migrate-images-ecr-to-gar.sh <new-tag>"
    echo ""
fi

