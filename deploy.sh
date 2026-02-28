#!/bin/bash
# =============================================================================
# MediAssist AI — AWS Deployment Script
# Team Cyber Scorpion | AI for Bharat Hackathon
# 
# WHAT THIS SCRIPT DOES (step by step):
#  1. Creates S3 bucket for document uploads
#  2. Creates DynamoDB tables for results and audit logs
#  3. Creates IAM role for Lambda
#  4. Deploys Lambda functions
#  5. Creates API Gateway with routes
#  6. Deploys frontend to S3 static website
#
# PREREQUISITES:
#  - AWS CLI installed and configured (run: aws configure)
#  - Your AWS credentials must have: S3, Lambda, DynamoDB, IAM, API Gateway permissions
#  - Python 3.11+ installed
#
# USAGE:
#  chmod +x deploy.sh
#  ./deploy.sh
# =============================================================================

set -e  # Exit on any error

# ── CONFIGURATION ── (Change these values if needed)
AWS_REGION="us-east-1"
PROJECT_NAME="mediassist-ai"
STAGE="prod"

# Auto-generate unique suffix to avoid S3 bucket name conflicts
SUFFIX=$(date +%s | tail -c 6)
S3_DOCS_BUCKET="${PROJECT_NAME}-documents-${SUFFIX}"
S3_FRONTEND_BUCKET="${PROJECT_NAME}-frontend-${SUFFIX}"
LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
LAMBDA_PROCESS_NAME="${PROJECT_NAME}-process-document"
LAMBDA_APPROVE_NAME="${PROJECT_NAME}-approve-document"
DYNAMODB_RESULTS_TABLE="MediAssist-Results"
DYNAMODB_AUDIT_TABLE="MediAssist-AuditLog"
API_NAME="${PROJECT_NAME}-api"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     MediAssist AI — AWS Deployment                      ║"
echo "║     Team Cyber Scorpion                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Region: $AWS_REGION"
echo "Project: $PROJECT_NAME"
echo ""

# Check AWS CLI is configured
echo "▶ Checking AWS credentials..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "❌ AWS credentials not configured."
  echo "   Run: aws configure"
  echo "   You'll need: Access Key ID, Secret Access Key, Region (us-east-1)"
  exit 1
fi
echo "✅ AWS Account: $AWS_ACCOUNT_ID"
echo ""

# ── STEP 1: Create S3 buckets ──
echo "▶ Step 1/7: Creating S3 buckets..."

# Documents bucket (private)
aws s3 mb "s3://${S3_DOCS_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true
aws s3api put-bucket-versioning \
  --bucket "$S3_DOCS_BUCKET" \
  --versioning-configuration Status=Enabled

# Block all public access on docs bucket (security)
aws s3api put-public-access-block \
  --bucket "$S3_DOCS_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "✅ Documents bucket: s3://${S3_DOCS_BUCKET}"

# Frontend bucket (public website)
aws s3 mb "s3://${S3_FRONTEND_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true

# Enable static website hosting
aws s3api put-bucket-website \
  --bucket "$S3_FRONTEND_BUCKET" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"index.html"}}'

# Allow public read for frontend
aws s3api put-public-access-block \
  --bucket "$S3_FRONTEND_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-policy \
  --bucket "$S3_FRONTEND_BUCKET" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"PublicReadGetObject\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${S3_FRONTEND_BUCKET}/*\"
    }]
  }"

echo "✅ Frontend bucket: s3://${S3_FRONTEND_BUCKET}"
echo ""

# ── STEP 2: Create DynamoDB Tables ──
echo "▶ Step 2/7: Creating DynamoDB tables..."

# Results table
aws dynamodb create-table \
  --table-name "$DYNAMODB_RESULTS_TABLE" \
  --attribute-definitions AttributeName=doc_id,AttributeType=S \
  --key-schema AttributeName=doc_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" 2>/dev/null || echo "  (Results table already exists, skipping)"

# Audit table
aws dynamodb create-table \
  --table-name "$DYNAMODB_AUDIT_TABLE" \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" 2>/dev/null || echo "  (Audit table already exists, skipping)"

# Enable TTL on audit table (auto-delete old records)
aws dynamodb update-time-to-live \
  --table-name "$DYNAMODB_AUDIT_TABLE" \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" \
  --region "$AWS_REGION" 2>/dev/null || true

echo "✅ DynamoDB tables created"
echo ""

# ── STEP 3: Create IAM Role for Lambda ──
echo "▶ Step 3/7: Creating IAM role for Lambda..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

# Create role (ignore error if already exists)
aws iam create-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --region "$AWS_REGION" 2>/dev/null || true

# Attach required policies
aws iam attach-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

# Custom policy for Bedrock + DynamoDB + S3
CUSTOM_POLICY="{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Action\": [\"bedrock:InvokeModel\"],
      \"Resource\": \"arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0\"
    },
    {
      \"Effect\": \"Allow\",
      \"Action\": [\"dynamodb:PutItem\",\"dynamodb:GetItem\",\"dynamodb:UpdateItem\",\"dynamodb:Query\"],
      \"Resource\": [
        \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_RESULTS_TABLE}\",
        \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_AUDIT_TABLE}\"
      ]
    },
    {
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:PutObject\",\"s3:GetObject\"],
      \"Resource\": \"arn:aws:s3:::${S3_DOCS_BUCKET}/*\"
    },
    {
      \"Effect\": \"Allow\",
      \"Action\": [\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],
      \"Resource\": \"*\"
    }
  ]
}"

aws iam put-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-name "${PROJECT_NAME}-policy" \
  --policy-document "$CUSTOM_POLICY" 2>/dev/null || true

LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
echo "✅ IAM Role: $LAMBDA_ROLE_ARN"
echo "   (Waiting 10s for IAM propagation...)"
sleep 10
echo ""

# ── STEP 4: Package and Deploy Lambda Functions ──
echo "▶ Step 4/7: Deploying Lambda functions..."

cd backend/lambda

# Package process_document
zip -q process_document.zip process_document.py
aws lambda create-function \
  --function-name "$LAMBDA_PROCESS_NAME" \
  --runtime python3.11 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler process_document.lambda_handler \
  --zip-file fileb://process_document.zip \
  --timeout 60 \
  --memory-size 256 \
  --environment "Variables={AUDIT_TABLE=${DYNAMODB_AUDIT_TABLE},RESULTS_TABLE=${DYNAMODB_RESULTS_TABLE},S3_BUCKET=${S3_DOCS_BUCKET}}" \
  --region "$AWS_REGION" 2>/dev/null || \
aws lambda update-function-code \
  --function-name "$LAMBDA_PROCESS_NAME" \
  --zip-file fileb://process_document.zip \
  --region "$AWS_REGION"

echo "✅ process_document Lambda deployed"

# Package approve_document
zip -q approve_document.zip approve_document.py
aws lambda create-function \
  --function-name "$LAMBDA_APPROVE_NAME" \
  --runtime python3.11 \
  --role "$LAMBDA_ROLE_ARN" \
  --handler approve_document.lambda_handler \
  --zip-file fileb://approve_document.zip \
  --timeout 30 \
  --memory-size 128 \
  --environment "Variables={AUDIT_TABLE=${DYNAMODB_AUDIT_TABLE},RESULTS_TABLE=${DYNAMODB_RESULTS_TABLE}}" \
  --region "$AWS_REGION" 2>/dev/null || \
aws lambda update-function-code \
  --function-name "$LAMBDA_APPROVE_NAME" \
  --zip-file fileb://approve_document.zip \
  --region "$AWS_REGION"

echo "✅ approve_document Lambda deployed"
rm -f process_document.zip approve_document.zip
cd ../..
echo ""

# ── STEP 5: Create API Gateway ──
echo "▶ Step 5/7: Creating API Gateway..."

# Create HTTP API (v2 - simpler and cheaper than REST API)
API_ID=$(aws apigatewayv2 create-api \
  --name "$API_NAME" \
  --protocol-type HTTP \
  --cors-configuration AllowOrigins="*",AllowMethods="*",AllowHeaders="*" \
  --region "$AWS_REGION" \
  --query ApiId --output text)

echo "  API ID: $API_ID"

PROCESS_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_PROCESS_NAME}"
APPROVE_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_APPROVE_NAME}"

# Create integrations
PROCESS_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id "$API_ID" \
  --integration-type AWS_PROXY \
  --integration-uri "$PROCESS_LAMBDA_ARN" \
  --payload-format-version "2.0" \
  --region "$AWS_REGION" \
  --query IntegrationId --output text)

APPROVE_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id "$API_ID" \
  --integration-type AWS_PROXY \
  --integration-uri "$APPROVE_LAMBDA_ARN" \
  --payload-format-version "2.0" \
  --region "$AWS_REGION" \
  --query IntegrationId --output text)

# Create routes
aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key "POST /process" \
  --target "integrations/${PROCESS_INTEGRATION_ID}" \
  --region "$AWS_REGION" > /dev/null

aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key "POST /approve" \
  --target "integrations/${APPROVE_INTEGRATION_ID}" \
  --region "$AWS_REGION" > /dev/null

# Create deployment stage
aws apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name "$STAGE" \
  --auto-deploy \
  --region "$AWS_REGION" > /dev/null

# Grant Lambda invoke permissions to API Gateway
aws lambda add-permission \
  --function-name "$LAMBDA_PROCESS_NAME" \
  --statement-id "apigateway-invoke-process" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/process" \
  --region "$AWS_REGION" 2>/dev/null || true

aws lambda add-permission \
  --function-name "$LAMBDA_APPROVE_NAME" \
  --statement-id "apigateway-invoke-approve" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/approve" \
  --region "$AWS_REGION" 2>/dev/null || true

API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE}"
echo "✅ API Gateway URL: $API_URL"
echo ""

# ── STEP 6: Update frontend with API URL and deploy ──
echo "▶ Step 6/7: Deploying frontend..."

# Inject API URL into the HTML
sed -i "s|https://YOUR_API_GATEWAY_URL|${API_URL}|g" frontend/index.html

# Upload to S3
aws s3 cp frontend/index.html "s3://${S3_FRONTEND_BUCKET}/index.html" \
  --content-type "text/html" \
  --cache-control "no-cache"

FRONTEND_URL="http://${S3_FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
echo "✅ Frontend deployed: $FRONTEND_URL"
echo ""

# ── STEP 7: Save deployment info ──
echo "▶ Step 7/7: Saving deployment info..."

cat > deployment-info.txt << EOF
MediAssist AI — Deployment Info
================================
Date: $(date)
AWS Account: ${AWS_ACCOUNT_ID}
Region: ${AWS_REGION}

URLs:
  Frontend:    ${FRONTEND_URL}
  API Base:    ${API_URL}
  API Process: ${API_URL}/process
  API Approve: ${API_URL}/approve

AWS Resources:
  S3 Docs:     ${S3_DOCS_BUCKET}
  S3 Frontend: ${S3_FRONTEND_BUCKET}
  DynamoDB:    ${DYNAMODB_RESULTS_TABLE}
  DynamoDB:    ${DYNAMODB_AUDIT_TABLE}
  Lambda:      ${LAMBDA_PROCESS_NAME}
  Lambda:      ${LAMBDA_APPROVE_NAME}
  API GW ID:   ${API_ID}
  IAM Role:    ${LAMBDA_ROLE_NAME}
EOF

echo "✅ Deployment info saved to: deployment-info.txt"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅ DEPLOYMENT COMPLETE!                                 ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "  🌐 Frontend:  $FRONTEND_URL"
echo "  🔌 API URL:   $API_URL"
echo "║                                                          ║"
echo "║  ⚠  NEXT STEPS:                                         ║"
echo "║  1. Enable Amazon Bedrock Claude 3 Haiku in AWS Console  ║"
echo "║     Go to: Bedrock > Model access > Request access       ║"
echo "║  2. Open the Frontend URL in your browser                ║"
echo "║  3. Upload a synthetic/public document to test           ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
