#!/bin/bash

# ================================================
# MediAssist AI — AWS Deployment Script
# EC2 Ollama already running — skips EC2 creation
# ================================================

set -e
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# ================================================
# Configuration
# ================================================
AWS_REGION="${AWS_REGION:-ap-south-1}"
S3_DOCS_BUCKET="mediassistai-documents"
S3_FRONTEND_BUCKET="mediassistai-frontend"
DYNAMODB_RESULTS_TABLE="MediAssist-Results"
DYNAMODB_USERS_TABLE="MediAssist-Users"
DYNAMODB_AUDIT_TABLE="MediAssist-AuditLog"

# ✅ Existing EC2 Ollama Server — no creation needed
EC2_PUBLIC_IP="3.109.55.138"
OLLAMA_MODEL="llama3.2:3b"
OLLAMA_PORT="11434"
OLLAMA_ENDPOINT="http://${EC2_PUBLIC_IP}:${OLLAMA_PORT}"

# Track created resources for rollback
CREATED_RESOURCES=()

# ================================================
# Error handler + Rollback
# ================================================
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
    echo "Rollback complete."
}

echo "================================================"
echo " MediAssist AI — AWS Deployment"
echo " Region  : $AWS_REGION"
echo " Ollama  : $OLLAMA_ENDPOINT"
echo " Model   : $OLLAMA_MODEL"
echo "================================================"

# ================================================
# Pre-flight: Check AWS credentials + Ollama
# ================================================
echo ""
echo "[0/6] Pre-flight checks..."

if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  ✓ AWS Account: $ACCOUNT_ID"

# Verify Ollama is reachable before deploying anything
echo "  Checking Ollama at $OLLAMA_ENDPOINT ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$OLLAMA_ENDPOINT/api/tags" || true)

if [ "$HTTP_CODE" == "200" ]; then
    echo "  ✓ Ollama is reachable!"
else
    echo ""
    echo "  ❌ Cannot reach Ollama at $OLLAMA_ENDPOINT (HTTP: $HTTP_CODE)"
    echo ""
    echo "  Fix checklist:"
    echo "  1. EC2 Security Group — open port 11434 inbound (0.0.0.0/0)"
    echo ""
    echo "  2. SSH into EC2 and check Ollama is running:"
    echo "     sudo systemctl status ollama"
    echo ""
    echo "  3. Make sure Ollama listens on 0.0.0.0:"
    echo "     sudo cat /etc/systemd/system/ollama.service.d/override.conf"
    echo "     # Should show: Environment=\"OLLAMA_HOST=0.0.0.0:11434\""
    echo ""
    echo "  If missing, run on EC2:"
    echo "     sudo mkdir -p /etc/systemd/system/ollama.service.d"
    echo "     echo '[Service]' | sudo tee /etc/systemd/system/ollama.service.d/override.conf"
    echo "     echo 'Environment=\"OLLAMA_HOST=0.0.0.0:11434\"' | sudo tee -a /etc/systemd/system/ollama.service.d/override.conf"
    echo "     sudo systemctl daemon-reload && sudo systemctl restart ollama"
    exit 1
fi

# ================================================
# Step 1: S3 Buckets
# ================================================
echo ""
echo "[1/6] Creating S3 buckets..."

if aws s3 ls "s3://$S3_DOCS_BUCKET" 2>/dev/null; then
    echo "  ℹ Docs bucket already exists: $S3_DOCS_BUCKET"
else
    aws s3 mb "s3://$S3_DOCS_BUCKET" --region "$AWS_REGION"
    CREATED_RESOURCES+=("s3:$S3_DOCS_BUCKET")
    echo "  ✓ Docs bucket created: $S3_DOCS_BUCKET"
fi

if aws s3 ls "s3://$S3_FRONTEND_BUCKET" 2>/dev/null; then
    echo "  ℹ Frontend bucket already exists: $S3_FRONTEND_BUCKET"
else
    aws s3 mb "s3://$S3_FRONTEND_BUCKET" --region "$AWS_REGION"
    CREATED_RESOURCES+=("s3:$S3_FRONTEND_BUCKET")
    echo "  ✓ Frontend bucket created: $S3_FRONTEND_BUCKET"
fi

aws s3 website "s3://$S3_FRONTEND_BUCKET" \
    --index-document index.html \
    --error-document error.html

aws s3api put-public-access-block \
    --bucket "$S3_FRONTEND_BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-bucket-policy \
    --bucket "$S3_FRONTEND_BUCKET" \
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
# Step 2: DynamoDB Tables
# ================================================
echo ""
echo "[2/6] Creating DynamoDB tables..."

create_dynamo_table() {
    local TABLE_NAME=$1
    local KEY_NAME=$2

    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo "  ℹ Already exists: $TABLE_NAME"
    else
        aws dynamodb create-table \
            --table-name "$TABLE_NAME" \
            --attribute-definitions AttributeName="$KEY_NAME",AttributeType=S \
            --key-schema AttributeName="$KEY_NAME",KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$AWS_REGION" > /dev/null
        CREATED_RESOURCES+=("dynamodb:$TABLE_NAME")
        echo "  ⏳ Waiting for $TABLE_NAME to be active..."
        aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
        echo "  ✓ Created: $TABLE_NAME"
    fi
}

create_dynamo_table "$DYNAMODB_RESULTS_TABLE" "doc_id"
create_dynamo_table "$DYNAMODB_USERS_TABLE"   "user_id"
create_dynamo_table "$DYNAMODB_AUDIT_TABLE"   "event_id"

echo "  ✓ DynamoDB ready."

# ================================================
# Step 3: IAM Role for Lambda
# ================================================
echo ""
echo "[3/6] Setting up IAM role for Lambda..."

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

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

    echo "  ✓ Role + policies created"
    sleep 10
fi

LAMBDA_ROLE_ARN=$(aws iam get-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --query 'Role.Arn' \
    --output text)

echo "  ✓ IAM ready."

# ================================================
# Step 4: Package and Deploy Lambda Functions
# ================================================
echo ""
echo "[4/6] Packaging Lambda functions..."

TMP_DIR="$PWD/.tmp"
mkdir -p "$TMP_DIR"
WIN_TMP_DIR=$(cd "$TMP_DIR" && pwd -W)

LAMBDA_SRC="../backend/lambda"

if [ ! -d "$LAMBDA_SRC" ]; then
    echo "❌ Lambda source not found at $LAMBDA_SRC"
    exit 1
fi

cd "$LAMBDA_SRC"

powershell.exe -Command "
New-Item -ItemType Directory -Force -Path '$WIN_TMP_DIR' | Out-Null;
Compress-Archive -Path * -DestinationPath '$WIN_TMP_DIR\lambda.zip' -Force
"

cd ../../infra
echo "  ✓ Lambda packaged"

deploy_lambda() {
    local FUNC_NAME=$1
    local HANDLER=$2
    local TIMEOUT=$3
    local MEMORY=$4

    # All Lambda functions get Ollama URL + model injected as env vars
    local ENV_VARS="Variables={\
OLLAMA_ENDPOINT=$OLLAMA_ENDPOINT,\
OLLAMA_MODEL=$OLLAMA_MODEL,\
RESULTS_TABLE=$DYNAMODB_RESULTS_TABLE,\
AUDIT_TABLE=$DYNAMODB_AUDIT_TABLE,\
DOCS_BUCKET=$S3_DOCS_BUCKET\
}"

    if aws lambda get-function --function-name "$FUNC_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo "  ↻ Updating: $FUNC_NAME"
        aws lambda update-function-code \
            --function-name "$FUNC_NAME" \
            --zip-file "fileb://$WIN_TMP_DIR/lambda.zip" \
            --region "$AWS_REGION" > /dev/null
        sleep 3
        aws lambda update-function-configuration \
            --function-name "$FUNC_NAME" \
            --environment "$ENV_VARS" \
            --region "$AWS_REGION" > /dev/null
    else
        echo "  + Creating: $FUNC_NAME"
        aws lambda create-function \
            --function-name "$FUNC_NAME" \
            --runtime python3.11 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler "$HANDLER" \
            --zip-file "fileb://$WIN_TMP_DIR/lambda.zip" \
            --timeout "$TIMEOUT" \
            --memory-size "$MEMORY" \
            --environment "$ENV_VARS" \
            --region "$AWS_REGION" > /dev/null
    fi

    echo "  ✓ $FUNC_NAME ready"
}

deploy_lambda "MediAssist-Process" "process_document.lambda_handler" 300 512
deploy_lambda "MediAssist-Approve" "approve_document.lambda_handler"  30  256
deploy_lambda "MediAssist-Audit"   "get_audit_log.lambda_handler"     30  256

echo "  ✓ Lambda functions ready."

# ================================================
# Step 5: API Gateway
# ================================================
echo ""
echo "[5/6] Setting up API Gateway..."

API_NAME="MediAssist-HTTP-API"

API_ID=$(aws apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiId" \
    --output text \
    --region "$AWS_REGION")

if [ -z "$API_ID" ] || [ "$API_ID" == "None" ]; then
    API_ID=$(aws apigatewayv2 create-api \
        --name "$API_NAME" \
        --protocol-type HTTP \
        --cors-configuration \
            AllowOrigins='["*"]',AllowMethods='["GET","POST","OPTIONS"]',AllowHeaders='["Content-Type","Authorization"]' \
        --query 'ApiId' \
        --output text \
        --region "$AWS_REGION")
    echo "  ✓ API created: $API_ID"
else
    echo "  ℹ API already exists: $API_ID"
fi

# Lambda invoke permissions
for FUNC in MediAssist-Process MediAssist-Approve MediAssist-Audit; do
    aws lambda add-permission \
        --function-name "$FUNC" \
        --statement-id "apigateway-${FUNC}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$AWS_REGION:$ACCOUNT_ID:$API_ID/*/*" \
        --region "$AWS_REGION" 2>/dev/null || true
done

# One integration per Lambda
create_integration() {
    local FUNC_NAME=$1
    aws apigatewayv2 create-integration \
        --api-id "$API_ID" \
        --integration-type AWS_PROXY \
        --integration-uri "arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$FUNC_NAME" \
        --payload-format-version 2.0 \
        --query 'IntegrationId' \
        --output text \
        --region "$AWS_REGION"
}

INT_PROCESS=$(create_integration "MediAssist-Process")
INT_APPROVE=$(create_integration "MediAssist-Approve")
INT_AUDIT=$(create_integration "MediAssist-Audit")

aws apigatewayv2 create-route --api-id "$API_ID" --route-key "POST /process" --target "integrations/$INT_PROCESS" --region "$AWS_REGION" 2>/dev/null || true
aws apigatewayv2 create-route --api-id "$API_ID" --route-key "POST /approve" --target "integrations/$INT_APPROVE" --region "$AWS_REGION" 2>/dev/null || true
aws apigatewayv2 create-route --api-id "$API_ID" --route-key "GET /audit"    --target "integrations/$INT_AUDIT"   --region "$AWS_REGION" 2>/dev/null || true

sleep 5

STAGE_EXISTS=$(aws apigatewayv2 get-stages \
    --api-id "$API_ID" \
    --query "Items[?StageName=='prod'].StageName" \
    --output text \
    --region "$AWS_REGION")

if [ -z "$STAGE_EXISTS" ] || [ "$STAGE_EXISTS" == "None" ]; then
    aws apigatewayv2 create-stage \
        --api-id "$API_ID" \
        --stage-name prod \
        --auto-deploy \
        --region "$AWS_REGION" > /dev/null
fi

API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
echo "  ✓ API Gateway: $API_URL"

# ================================================
# Step 6: Build & Deploy React Frontend
# ================================================
echo ""
echo "[6/6] Building and deploying React frontend..."

cat > ../frontend/.env.production <<EOF
VITE_API_BASE_URL=$API_URL
EOF

cd ../frontend
npm install
npm run build
cd ../infra

if [ ! -d "../frontend/dist" ]; then
    echo "❌ React build not found at frontend/dist!"
    exit 1
fi

aws s3 sync ../frontend/dist/ "s3://$S3_FRONTEND_BUCKET" --delete
echo "  ✓ Frontend deployed"

# ================================================
# Done!
# ================================================
echo ""
echo "================================================"
echo " ✅ DEPLOYMENT COMPLETE — MediAssist AI"
echo "================================================"
echo ""
echo "🖥️  Ollama (EC2)"
echo "   IP       : $EC2_PUBLIC_IP"
echo "   Endpoint : $OLLAMA_ENDPOINT"
echo "   Model    : $OLLAMA_MODEL"
echo "   Test     : curl $OLLAMA_ENDPOINT/api/tags"
echo ""
echo "☁️  AWS Resources"
echo "   API      : $API_URL"
echo "   Frontend : http://$S3_FRONTEND_BUCKET.s3-website.${AWS_REGION}.amazonaws.com"
echo "   Lambda   : MediAssist-Process | MediAssist-Approve | MediAssist-Audit"
echo "   DynamoDB : $DYNAMODB_RESULTS_TABLE | $DYNAMODB_USERS_TABLE | $DYNAMODB_AUDIT_TABLE"
echo ""
echo "================================================"

# Save config
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
EC2_PUBLIC_IP=$EC2_PUBLIC_IP
OLLAMA_ENDPOINT=$OLLAMA_ENDPOINT
OLLAMA_MODEL=$OLLAMA_MODEL
DEPLOYMENT_DATE=$(date)
CONFIG

echo "💾 Config saved to deployment-config.txt"