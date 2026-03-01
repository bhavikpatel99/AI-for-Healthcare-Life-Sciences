#!/bin/bash

# ================================================
# MediAssist AI — Resource Cleanup Script
# ================================================

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "================================================"
echo " MediAssist AI — Resource Cleanup Script"
echo "================================================"

# List all tables to clean up
DYNAMODB_TABLES=(
    "MediAssist-Results"
    "MediAssist-Users"
    "MediAssist-AuditLog"
)

# List all Lambda functions to clean up
LAMBDA_FUNCTIONS=(
    "MediAssist-DocumentProcessor"
    "MediAssist-ResultsRetrieval"
)

IAM_ROLE="MediAssist-Lambda-Role"

echo "⚠️  WARNING: This will delete the following resources:"
for table in "${DYNAMODB_TABLES[@]}"; do
    echo "  • DynamoDB table: $table"
done
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    echo "  • Lambda function: $func"
done
echo "  • IAM role: $IAM_ROLE"
echo "  • All S3 buckets starting with: mediassist-ai-*"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Starting cleanup..."

# ================================================
# Step 1: Delete DynamoDB Tables
# ================================================
echo "[1/5] Deleting DynamoDB tables..."
for table in "${DYNAMODB_TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$table" --region "$AWS_REGION" &>/dev/null; then
        aws dynamodb delete-table --table-name "$table" --region "$AWS_REGION" > /dev/null
        echo "  ✓ Deleted: $table"
    else
        echo "  ℹ Table not found: $table"
    fi
done

# ================================================
# Step 2: Delete Lambda Functions
# ================================================
echo "[2/5] Deleting Lambda functions..."
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$func" &>/dev/null; then
        aws lambda delete-function --function-name "$func"
        echo "  ✓ Deleted: $func"
    else
        echo "  ℹ Function not found: $func"
    fi
done

# ================================================
# Step 3: Delete IAM Role
# ================================================
echo "[3/5] Deleting IAM role..."
if aws iam get-role --role-name "$IAM_ROLE" &>/dev/null; then
    # Detach all policies first
    POLICIES=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $POLICIES; do
        aws iam detach-role-policy --role-name "$IAM_ROLE" --policy-arn "$policy"
    done
    aws iam delete-role --role-name "$IAM_ROLE"
    echo "  ✓ Deleted: $IAM_ROLE"
else
    echo "  ℹ Role not found: $IAM_ROLE"
fi

# ================================================
# Step 4: Delete S3 Buckets
# ================================================
echo "[4/5] Deleting S3 buckets..."
BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `mediassist-ai-`)].Name' --output text)
if [ -n "$BUCKETS" ]; then
    for bucket in $BUCKETS; do
        echo "  🗑️  Emptying and deleting: $bucket"
        aws s3 rb "s3://$bucket" --force 2>/dev/null || echo "  ⚠️  Could not delete: $bucket"
    done
    echo "  ✓ S3 buckets cleaned up"
else
    echo "  ℹ No MediAssist buckets found"
fi

# ================================================
# Step 5: API Gateway (placeholder)
# ================================================
echo "[5/5] Checking for API Gateway..."
echo "  ℹ API Gateway cleanup not implemented yet"

echo ""
echo "================================================"
echo " ✅ CLEANUP COMPLETE"
echo "================================================"
echo "You can now run ./deploy.sh for a fresh deployment."