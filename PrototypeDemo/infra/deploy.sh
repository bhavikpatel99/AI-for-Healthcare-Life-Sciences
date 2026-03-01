#!/bin/bash

# ================================================
# MediAssist AI — AWS Deployment Script
# Fixed version with idempotent resource creation
# ================================================

set -e  # Exit on error
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
RANDOM_SUFFIX=$(date +%s | tail -c 6)
S3_DOCS_BUCKET="mediassist-ai-documents-${RANDOM_SUFFIX}"
S3_FRONTEND_BUCKET="mediassist-ai-frontend-${RANDOM_SUFFIX}"
DYNAMODB_RESULTS_TABLE="MediAssist-Results"
DYNAMODB_USERS_TABLE="MediAssist-Users"
DYNAMODB_AUDIT_TABLE="MediAssist-AuditLog"

# Track created resources for rollback
CREATED_RESOURCES=()

# Error handler
handle_error() {
    local line=$1
    local command=$2
    echo "================================================"
    echo " ERROR DETECTED — Rolling back..."
    echo " Line: $line | Command: $command"
    echo "================================================"
    rollback
    exit 1
}

# Rollback function
rollback() {
    echo "Rolling back newly created resources..."
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name <<< "$resource"
        case $type in
            s3)
                echo "  Removing S3 bucket: $name"
                aws s3 rb "s3://$name" --force 2>/dev/null || true
                ;;
            dynamodb)
                echo "  Removing DynamoDB table: $name"
                aws dynamodb delete-table --table-name "$name" --region "$AWS_REGION" 2>/dev/null || true
                ;;
        esac
    done
    echo "================================================"
    echo " Rollback complete."
    echo "================================================"
}

echo "================================================"
echo " MediAssist AI — AWS Deployment Script"
echo "================================================"

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Using account: $ACCOUNT_ID in region: $AWS_REGION"

# ================================================
# Step 1: Create S3 Buckets
# ================================================
echo "[1/7] Creating S3 buckets..."

# Documents bucket
if aws s3 ls "s3://$S3_DOCS_BUCKET" 2>/dev/null; then
    echo "  ℹ Docs bucket already exists: $S3_DOCS_BUCKET"
else
    aws s3 mb "s3://$S3_DOCS_BUCKET" --region "$AWS_REGION"
    CREATED_RESOURCES+=("s3:$S3_DOCS_BUCKET")
    echo "  ✓ Docs bucket created: $S3_DOCS_BUCKET"
fi

# Frontend bucket
if aws s3 ls "s3://$S3_FRONTEND_BUCKET" 2>/dev/null; then
    echo "  ℹ Frontend bucket already exists: $S3_FRONTEND_BUCKET"
else
    aws s3 mb "s3://$S3_FRONTEND_BUCKET" --region "$AWS_REGION"
    CREATED_RESOURCES+=("s3:$S3_FRONTEND_BUCKET")
    echo "  ✓ Frontend bucket created: $S3_FRONTEND_BUCKET"
fi

# Configure frontend bucket for static website hosting
aws s3 website "s3://$S3_FRONTEND_BUCKET" --index-document index.html --error-document error.html

echo "Configuring public access..."

aws s3api put-public-access-block \
    --bucket $S3_FRONTEND_BUCKET \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-policy \
    --bucket $S3_FRONTEND_BUCKET \
    --policy "{
        \"Version\":\"2012-10-17\",
        \"Statement\":[{
            \"Sid\":\"PublicReadGetObject\",
            \"Effect\":\"Allow\",
            \"Principal\":\"*\",
            \"Action\":\"s3:GetObject\",
            \"Resource\":\"arn:aws:s3:::$S3_FRONTEND_BUCKET/*\"
        }]
    }"

echo "  ✓ S3 ready."

# ================================================
# Step 2: Create DynamoDB Tables
# ================================================
echo "[2/7] Creating DynamoDB tables..."

# Results table
if aws dynamodb describe-table --table-name "$DYNAMODB_RESULTS_TABLE" --region "$AWS_REGION" &>/dev/null; then
    echo "  ℹ Results table already exists: $DYNAMODB_RESULTS_TABLE"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_RESULTS_TABLE" \
        --attribute-definitions AttributeName=doc_id,AttributeType=S \
        --key-schema AttributeName=doc_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" > /dev/null
    CREATED_RESOURCES+=("dynamodb:$DYNAMODB_RESULTS_TABLE")
    echo "  ✓ Results table created: $DYNAMODB_RESULTS_TABLE"
    
    # Wait for table to be active
    echo "  ⏳ Waiting for Results table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_RESULTS_TABLE" --region "$AWS_REGION"
fi

# Users table
if aws dynamodb describe-table --table-name "$DYNAMODB_USERS_TABLE" --region "$AWS_REGION" &>/dev/null; then
    echo "  ℹ Users table already exists: $DYNAMODB_USERS_TABLE"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_USERS_TABLE" \
        --attribute-definitions AttributeName=user_id,AttributeType=S \
        --key-schema AttributeName=user_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" > /dev/null
    CREATED_RESOURCES+=("dynamodb:$DYNAMODB_USERS_TABLE")
    echo "  ✓ Users table created: $DYNAMODB_USERS_TABLE"
    
    # Wait for table to be active
    echo "  ⏳ Waiting for Users table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_USERS_TABLE" --region "$AWS_REGION"
fi

# Audit Log table
if aws dynamodb describe-table --table-name "$DYNAMODB_AUDIT_TABLE" --region "$AWS_REGION" &>/dev/null; then
    echo "  ℹ Audit Log table already exists: $DYNAMODB_AUDIT_TABLE"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_AUDIT_TABLE" \
        --attribute-definitions AttributeName=event_id,AttributeType=S \
        --key-schema AttributeName=event_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" > /dev/null
    CREATED_RESOURCES+=("dynamodb:$DYNAMODB_AUDIT_TABLE")
    echo "  ✓ Audit Log table created: $DYNAMODB_AUDIT_TABLE"
    
    # Wait for table to be active
    echo "  ⏳ Waiting for Audit Log table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_AUDIT_TABLE" --region "$AWS_REGION"
fi

echo "  ✓ DynamoDB ready."

# ================================================
# Step 3: Create IAM Role for Lambda
# ================================================
echo "[3/7] Creating IAM role for Lambda..."

LAMBDA_ROLE_NAME="MediAssist-Lambda-Role"

if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
    echo "  ℹ Lambda role already exists: $LAMBDA_ROLE_NAME"
else
    aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' > /dev/null

    echo "  ✓ Lambda role created: $LAMBDA_ROLE_NAME"

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

    echo "  ✓ Policies attached"
    sleep 10
fi

LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)
echo "  ✓ IAM ready."

# ================================================
# Step 4: Package and Deploy Lambda Functions
# ================================================
echo "[4/7] Packaging Lambda functions..."

TMP_DIR="$PWD/.tmp"
mkdir -p "$TMP_DIR"

# Convert to Windows path
WIN_TMP_DIR=$(cd "$TMP_DIR" && pwd -W)

LAMBDA_SRC="../backend/lambda"

if [ ! -d "$LAMBDA_SRC" ]; then
  echo "❌ ERROR: Lambda folder not found at $LAMBDA_SRC"
  exit 1
fi

echo "📦 Packaging ALL Lambda handlers..."

cd $LAMBDA_SRC

powershell.exe -Command "
New-Item -ItemType Directory -Force -Path '$WIN_TMP_DIR' | Out-Null;
Compress-Archive -Path * -DestinationPath '$WIN_TMP_DIR\lambda.zip' -Force
"

cd ../../infra

echo "✓ Lambda packaged successfully"

echo "[5/7] Deploying Lambda functions..."

# Deploy document processor Lambda
aws lambda create-function \
  --function-name MediAssist-Process \
  --runtime python3.11 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler process_document.lambda_handler \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip" \
  --timeout 300 \
  --memory-size 512 || \
aws lambda update-function-code \
  --function-name MediAssist-Process \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip"

  aws lambda create-function \
  --function-name MediAssist-Approve \
  --runtime python3.11 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler approve_document.lambda_handler \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip" \
  --timeout 30 \
  --memory-size 256 || \
aws lambda update-function-code \
  --function-name MediAssist-Approve \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip"

  aws lambda create-function \
  --function-name MediAssist-Audit \
  --runtime python3.11 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler get_audit_log.lambda_handler \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip" \
  --timeout 30 \
  --memory-size 256 || \
aws lambda update-function-code \
  --function-name MediAssist-Audit \
  --zip-file "fileb://$WIN_TMP_DIR/lambda.zip"

echo "  ✓ Lambda functions ready."

# ================================================
# Step 6: Create API Gateway
# ================================================
echo "[6/7] Setting up API Gateway..."

API_NAME="MediAssist-HTTP-API"

API_ID=$(aws apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiId" \
    --output text)

if [ -z "$API_ID" ]; then
    echo "Creating API..."

    API_ID=$(aws apigatewayv2 create-api \
        --name "$API_NAME" \
        --protocol-type HTTP \
        --query 'ApiId' \
        --output text)

    echo "API Created: $API_ID"

    aws lambda add-permission \
  --function-name MediAssist-Process \
  --statement-id apigateway-access-process \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/*/*" || true

aws lambda add-permission \
  --function-name MediAssist-Approve \
  --statement-id apigateway-access-approve \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/*/*" || true

aws lambda add-permission \
  --function-name MediAssist-Audit \
  --statement-id apigateway-access-audit \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/*/*" || true
fi

echo "Ensuring Integration exists..."

INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
    --api-id $API_ID \
    --query 'Items[0].IntegrationId' \
    --output text)

if [ "$INTEGRATION_ID" == "None" ] || [ -z "$INTEGRATION_ID" ]; then
    INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id $API_ID \
        --integration-type AWS_PROXY \
        --integration-uri arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:MediAssist-DocumentProcessor \
        --payload-format-version 2.0 \
        --query 'IntegrationId' \
        --output text)
fi

echo "Ensuring Routes exist..."

aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "POST /process" \
    --target "integrations/$INTEGRATION_ID" 2>/dev/null || true

aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "POST /approve" \
    --target "integrations/$INTEGRATION_ID" 2>/dev/null || true

aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "GET /audit" \
    --target "integrations/$INTEGRATION_ID" 2>/dev/null || true


echo "⏳ Waiting for routes to register..."
sleep 5


echo "Deploying API..."
aws apigatewayv2 create-deployment \
    --api-id $API_ID \
    --description "Auto deployment" \
    > /dev/null || true


echo "Ensuring Stage exists..."

STAGE_EXISTS=$(aws apigatewayv2 get-stages \
    --api-id $API_ID \
    --query "Items[?StageName=='prod'].StageName" \
    --output text)

if [ -z "$STAGE_EXISTS" ]; then
    aws apigatewayv2 create-stage \
        --api-id $API_ID \
        --stage-name prod \
        --auto-deploy
fi

STAGE="prod"
API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE}"

echo "API URL: $API_URL"
# ================================================
# Step 7: Deploy Frontend
# ================================================
echo "Creating React ENV..."

cat > ../frontend/.env.production <<EOF
VITE_API_BASE_URL=$API_URL
EOF

echo "Building React..."

cd ../frontend
npm install
npm run build
cd ../infra

echo "Deploying frontend..."

if [ ! -d "../frontend/dist" ]; then
  echo "❌ Build output not found!"
  exit 1
fi

aws s3 sync ../frontend/dist/ "s3://$S3_FRONTEND_BUCKET" --delete

echo "  ✓ Frontend deployed"
    
# ================================================
# Deployment Complete
# ================================================
echo ""
echo "================================================"
echo " ✅ DEPLOYMENT SUCCESSFUL"
echo "================================================"
echo ""
echo "📋 Resource Summary:"
echo "  • S3 Documents Bucket: $S3_DOCS_BUCKET"
echo "  • S3 Frontend Bucket: $S3_FRONTEND_BUCKET"
echo "  • DynamoDB Results Table: $DYNAMODB_RESULTS_TABLE"
echo "  • DynamoDB Users Table: $DYNAMODB_USERS_TABLE"
echo "  • DynamoDB Audit Log Table: $DYNAMODB_AUDIT_TABLE"
echo "  • Lambda Role: $LAMBDA_ROLE_NAME"
echo "  • Lambda Functions: MediAssist-DocumentProcessor, MediAssist-ResultsRetrieval"
echo ""
echo "🌐 Frontend URL: http://$S3_FRONTEND_BUCKET.s3-website-$AWS_REGION.amazonaws.com"
echo ""
echo "================================================"

# Save configuration
cat > deployment-config.txt <<CONFIG
AWS_REGION=$AWS_REGION
S3_DOCS_BUCKET=$S3_DOCS_BUCKET
S3_FRONTEND_BUCKET=$S3_FRONTEND_BUCKET
DYNAMODB_RESULTS_TABLE=$DYNAMODB_RESULTS_TABLE
DYNAMODB_USERS_TABLE=$DYNAMODB_USERS_TABLE
DYNAMODB_AUDIT_TABLE=$DYNAMODB_AUDIT_TABLE
LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN
ACCOUNT_ID=$ACCOUNT_ID
API_URL=$API_URL
DEPLOYMENT_DATE="$(date)"
CONFIG

echo "💾 Configuration saved to deployment-config.txt"
echo ""