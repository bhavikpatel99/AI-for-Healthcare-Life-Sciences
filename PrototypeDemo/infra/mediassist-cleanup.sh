#!/bin/bash

set +e

AWS_REGION="us-east-1"
PROJECT_NAME="mediassist-ai"

echo "======================================"
echo "  MediAssist FULL AWS Cleanup"
echo "======================================"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account: $ACCOUNT_ID"
echo ""

######################################
# DELETE LAMBDA FUNCTIONS
######################################

echo "Deleting Lambda functions..."

aws lambda delete-function \
  --function-name mediassist-ai-process-document \
  --region $AWS_REGION 2>/dev/null

aws lambda delete-function \
  --function-name mediassist-ai-approve-document \
  --region $AWS_REGION 2>/dev/null

aws lambda delete-function \
  --function-name mediassist-ai-audit-log \
  --region $AWS_REGION 2>/dev/null

echo "Lambda cleanup done"
echo ""

######################################
# DELETE API GATEWAY
######################################

echo "Deleting API Gateway..."

API_IDS=$(aws apigateway get-rest-apis \
  --query "items[?contains(name, 'mediassist')].id" \
  --output text \
  --region $AWS_REGION)

for API_ID in $API_IDS
do
  echo "Deleting API: $API_ID"
  aws apigateway delete-rest-api \
    --rest-api-id $API_ID \
    --region $AWS_REGION
done

echo "API Gateway cleanup done"
echo ""

######################################
# DELETE DYNAMODB
######################################

echo "Deleting DynamoDB tables..."

aws dynamodb delete-table \
  --table-name MediAssist-Results \
  --region $AWS_REGION 2>/dev/null

aws dynamodb delete-table \
  --table-name MediAssist-AuditLog \
  --region $AWS_REGION 2>/dev/null

echo "DynamoDB cleanup done"
echo ""

######################################
# DELETE IAM ROLE
######################################

echo "Deleting IAM role..."

aws iam detach-role-policy \
  --role-name mediassist-ai-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null

aws iam delete-role-policy \
  --role-name mediassist-ai-lambda-role \
  --policy-name mediassist-policy \
  2>/dev/null

aws iam delete-role \
  --role-name mediassist-ai-lambda-role \
  2>/dev/null

echo "IAM cleanup done"
echo ""

######################################
# DELETE S3 BUCKETS
######################################

echo "Deleting S3 buckets..."

BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'mediassist-ai')].Name" \
  --output text)

for BUCKET in $BUCKETS
do
  echo "Removing bucket: $BUCKET"
  aws s3 rm s3://$BUCKET --recursive 2>/dev/null
  aws s3 rb s3://$BUCKET --force 2>/dev/null
done

echo "S3 cleanup done"
echo ""

echo "======================================"
echo "  Cleanup COMPLETE ✅"
echo "======================================"