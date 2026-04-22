#!/bin/bash

# ================================================
# MediAssist AI — AWS Teardown & Cleanup Script
# Stops and deletes ALL deployed resources
# ================================================

set -e

AWS_REGION="${AWS_REGION:-ap-south-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "  MediAssist AI — Teardown & Cleanup Script"
echo "================================================"
echo ""
echo -e "${RED}⚠  WARNING: This will PERMANENTLY DELETE all MediAssist AWS resources!${NC}"
echo ""
read -p "Are you sure you want to continue? Type 'yes' to confirm: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# ------------------------------------------------
# Load config from deployment if available
# ------------------------------------------------
if [ -f "deployment-config.txt" ]; then
    echo ""
    echo "📂 Loading config from deployment-config.txt..."
    source deployment-config.txt
    echo "  ✓ Config loaded."
else
    echo ""
    echo -e "${YELLOW}⚠  deployment-config.txt not found. Using fallback detection.${NC}"
fi

# Check AWS credentials
echo ""
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  ✓ Using account: $ACCOUNT_ID in region: $AWS_REGION"

ERRORS=0

# ================================================
# Step 1: Delete API Gateway
# ================================================
echo ""
echo "[1/6] Deleting API Gateway..."

API_NAME="MediAssist-HTTP-API"
API_ID=$(aws apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiId" \
    --output text 2>/dev/null)

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
    aws apigatewayv2 delete-api --api-id "$API_ID" 2>/dev/null && \
        echo "  ✓ API Gateway deleted: $API_NAME ($API_ID)" || \
        { echo "  ❌ Failed to delete API Gateway"; ERRORS=$((ERRORS+1)); }
else
    echo "  ℹ API Gateway not found, skipping."
fi

# ================================================
# Step 2: Delete Lambda Functions
# ================================================
echo ""
echo "[2/6] Deleting Lambda functions..."

LAMBDA_FUNCTIONS=(
    "MediAssist-Process"
    "MediAssist-Approve"
    "MediAssist-Audit"
    "MediAssist-DocumentProcessor"
    "MediAssist-ResultsRetrieval"
)

for FUNC in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$FUNC" --region "$AWS_REGION" &>/dev/null; then
        aws lambda delete-function \
            --function-name "$FUNC" \
            --region "$AWS_REGION" 2>/dev/null && \
            echo "  ✓ Lambda deleted: $FUNC" || \
            { echo "  ❌ Failed to delete Lambda: $FUNC"; ERRORS=$((ERRORS+1)); }
    else
        echo "  ℹ Lambda not found, skipping: $FUNC"
    fi
done

# ================================================
# Step 3: Detach Policies & Delete IAM Role
# ================================================
echo ""
echo "[3/6] Deleting IAM role..."

LAMBDA_ROLE_NAME="MediAssist-Lambda-Role"

if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then

    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null)

    for POLICY_ARN in $ATTACHED_POLICIES; do
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "$POLICY_ARN" 2>/dev/null && \
            echo "  ✓ Detached policy: $POLICY_ARN" || \
            { echo "  ❌ Failed to detach policy: $POLICY_ARN"; ERRORS=$((ERRORS+1)); }
    done

    aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null && \
        echo "  ✓ IAM role deleted: $LAMBDA_ROLE_NAME" || \
        { echo "  ❌ Failed to delete IAM role"; ERRORS=$((ERRORS+1)); }
else
    echo "  ℹ IAM role not found, skipping."
fi

# ================================================
# Step 4: Delete DynamoDB Tables
# ================================================
echo ""
echo "[4/6] Deleting DynamoDB tables..."

DYNAMODB_TABLES=(
    "MediAssist-Results"
    "MediAssist-Users"
    "MediAssist-AuditLog"
)

for TABLE in "${DYNAMODB_TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$TABLE" --region "$AWS_REGION" &>/dev/null; then
        aws dynamodb delete-table \
            --table-name "$TABLE" \
            --region "$AWS_REGION" > /dev/null 2>&1 && \
            echo "  ✓ DynamoDB table deleted: $TABLE" || \
            { echo "  ❌ Failed to delete table: $TABLE"; ERRORS=$((ERRORS+1)); }
    else
        echo "  ℹ DynamoDB table not found, skipping: $TABLE"
    fi
done

# ================================================
# Step 5: Empty & Delete S3 Buckets
# ================================================
echo ""
echo "[5/6] Deleting S3 buckets..."

# Auto-discover MediAssist buckets if config not loaded
if [ -z "$S3_DOCS_BUCKET" ] || [ -z "$S3_FRONTEND_BUCKET" ]; then
    echo "  🔍 Auto-detecting MediAssist S3 buckets..."
    MEDIASSIST_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'mediassist-ai')].Name" \
        --output text 2>/dev/null)
else
    MEDIASSIST_BUCKETS="$S3_DOCS_BUCKET $S3_FRONTEND_BUCKET"
fi

if [ -z "$MEDIASSIST_BUCKETS" ] || [ "$MEDIASSIST_BUCKETS" == "None" ]; then
    echo "  ℹ No MediAssist S3 buckets found."
else
    for BUCKET in $MEDIASSIST_BUCKETS; do
        echo "  🗑  Emptying bucket: $BUCKET"
        # Delete all objects
        aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null || true
        # Delete all versions (for versioned buckets)
        VERSIONS=$(aws s3api list-object-versions \
            --bucket "$BUCKET" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null)
        if [ "$VERSIONS" != "null" ] && [ -n "$VERSIONS" ]; then
            echo "$VERSIONS" | jq -c '.[]' | while read -r OBJ; do
                KEY=$(echo "$OBJ" | jq -r '.Key')
                VID=$(echo "$OBJ" | jq -r '.VersionId')
                aws s3api delete-object \
                    --bucket "$BUCKET" \
                    --key "$KEY" \
                    --version-id "$VID" 2>/dev/null || true
            done
        fi
        # Delete the bucket
        aws s3 rb "s3://$BUCKET" --force 2>/dev/null && \
            echo "  ✓ S3 bucket deleted: $BUCKET" || \
            { echo "  ❌ Failed to delete bucket: $BUCKET"; ERRORS=$((ERRORS+1)); }
    done
fi

# ================================================
# Step 6: Clean up local files
# ================================================
echo ""
echo "[6/6] Cleaning up local deployment files..."

[ -f "deployment-config.txt" ]   && rm -f deployment-config.txt   && echo "  ✓ Removed deployment-config.txt"
[ -d ".tmp" ]                     && rm -rf .tmp                   && echo "  ✓ Removed .tmp directory"
[ -f "../frontend/.env.production" ] && rm -f ../frontend/.env.production && echo "  ✓ Removed .env.production"

# ================================================
# Done
# ================================================
echo ""
echo "================================================"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN} ✅ TEARDOWN COMPLETE — All resources deleted.${NC}"
else
    echo -e "${YELLOW} ⚠  TEARDOWN COMPLETE WITH $ERRORS ERROR(S).${NC}"
    echo "    Some resources may need manual cleanup in the AWS Console."
fi
echo "================================================"
echo ""