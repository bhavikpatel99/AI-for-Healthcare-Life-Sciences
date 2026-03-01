#!/bin/bash
set -e

AWS_REGION="us-east-1"
PROJECT_NAME="mediassist-ai"
STAGE="prod"

SUFFIX=$(date +%s | tail -c 6)

S3_DOCS_BUCKET="${PROJECT_NAME}-documents-${SUFFIX}"
S3_FRONTEND_BUCKET="${PROJECT_NAME}-frontend-${SUFFIX}"

LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
LAMBDA_PROCESS_NAME="${PROJECT_NAME}-process-document"
LAMBDA_APPROVE_NAME="${PROJECT_NAME}-approve-document"
LAMBDA_AUDIT_NAME="${PROJECT_NAME}-audit-log"

DYNAMODB_RESULTS_TABLE="MediAssist-Results"
DYNAMODB_AUDIT_TABLE="MediAssist-AuditLog"

echo "Checking AWS..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Using account: $AWS_ACCOUNT_ID"

echo "Creating S3 buckets..."
aws s3 mb s3://${S3_DOCS_BUCKET} --region $AWS_REGION 2>/dev/null || true
aws s3 mb s3://${S3_FRONTEND_BUCKET} --region $AWS_REGION 2>/dev/null || true

aws s3api put-bucket-website 
--bucket $S3_FRONTEND_BUCKET 
--website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"index.html"}}'

aws s3api put-bucket-policy 
--bucket $S3_FRONTEND_BUCKET 
--policy "{
"Version":"2012-10-17",
"Statement":[{
"Effect":"Allow",
"Principal":"*",
"Action":"s3:GetObject",
"Resource":"arn:aws:s3:::${S3_FRONTEND_BUCKET}/*"
}]
}"

echo "Creating DynamoDB tables..."
aws dynamodb create-table 
--table-name $DYNAMODB_RESULTS_TABLE 
--attribute-definitions AttributeName=doc_id,AttributeType=S 
--key-schema AttributeName=doc_id,KeyType=HASH 
--billing-mode PAY_PER_REQUEST 
--region $AWS_REGION 2>/dev/null || true

aws dynamodb create-table 
--table-name $DYNAMODB_AUDIT_TABLE 
--attribute-definitions AttributeName=event_id,AttributeType=S 
--key-schema AttributeName=event_id,KeyType=HASH 
--billing-mode PAY_PER_REQUEST 
--region $AWS_REGION 2>/dev/null || true

echo "Creating IAM Role..."
aws iam create-role 
--role-name $LAMBDA_ROLE_NAME 
--assume-role-policy-document '{
"Version":"2012-10-17",
"Statement":[{
"Effect":"Allow",
"Principal":{"Service":"lambda.amazonaws.com"},
"Action":"sts:AssumeRole"
}]
}' 2>/dev/null || true

aws iam attach-role-policy 
--role-name $LAMBDA_ROLE_NAME 
--policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy 
--role-name $LAMBDA_ROLE_NAME 
--policy-name mediassist-policy 
--policy-document "{
"Version":"2012-10-17",
"Statement":[
{"Effect":"Allow","Action":["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream"],"Resource":"*"},
{"Effect":"Allow","Action":["dynamodb:*"],"Resource":"*"},
{"Effect":"Allow","Action":["s3:*"],"Resource":"*"}
]
}"

sleep 10
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

echo "Packaging Lambdas..."
cd backend/lambda
zip process.zip process_document.py
zip approve.zip approve_document.py
zip audit.zip get_audit_log.py

echo "Deploying Lambdas..."
aws lambda create-function 
--function-name $LAMBDA_PROCESS_NAME 
--runtime python3.11 
--role $ROLE_ARN 
--handler process_document.lambda_handler 
--zip-file fileb://process.zip 
--timeout 60 
--memory-size 512 
--environment "Variables={AUDIT_TABLE=${DYNAMODB_AUDIT_TABLE},RESULTS_TABLE=${DYNAMODB_RESULTS_TABLE},S3_BUCKET=${S3_DOCS_BUCKET},AWS_REGION=${AWS_REGION}}" 
--region $AWS_REGION 2>/dev/null || 
aws lambda update-function-code --function-name $LAMBDA_PROCESS_NAME --zip-file fileb://process.zip --region $AWS_REGION

aws lambda create-function 
--function-name $LAMBDA_APPROVE_NAME 
--runtime python3.11 
--role $ROLE_ARN 
--handler approve_document.lambda_handler 
--zip-file fileb://approve.zip 
--timeout 30 
--memory-size 256 
--environment "Variables={AUDIT_TABLE=${DYNAMODB_AUDIT_TABLE},RESULTS_TABLE=${DYNAMODB_RESULTS_TABLE},AWS_REGION=${AWS_REGION}}" 
--region $AWS_REGION 2>/dev/null || 
aws lambda update-function-code --function-name $LAMBDA_APPROVE_NAME --zip-file fileb://approve.zip --region $AWS_REGION

aws lambda create-function 
--function-name $LAMBDA_AUDIT_NAME 
--runtime python3.11 
--role $ROLE_ARN 
--handler get_audit_log.lambda_handler 
--zip-file fileb://audit.zip 
--timeout 30 
--memory-size 256 
--environment "Variables={AUDIT_TABLE=${DYNAMODB_AUDIT_TABLE},AWS_REGION=${AWS_REGION}}" 
--region $AWS_REGION 2>/dev/null || 
aws lambda update-function-code --function-name $LAMBDA_AUDIT_NAME --zip-file fileb://audit.zip --region $AWS_REGION

cd ../..

echo "Creating API..."
API_ID=$(aws apigatewayv2 create-api --name mediassist-api --protocol-type HTTP --cors-configuration AllowOrigins="*" --region $AWS_REGION --query ApiId --output text)

PROC_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_PROCESS_NAME}"
APPR_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_APPROVE_NAME}"
AUDIT_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_AUDIT_NAME}"

PROC_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY --integration-uri $PROC_ARN --payload-format-version 2.0 --region $AWS_REGION --query IntegrationId --output text)
APPR_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY --integration-uri $APPR_ARN --payload-format-version 2.0 --region $AWS_REGION --query IntegrationId --output text)
AUD_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY --integration-uri $AUDIT_ARN --payload-format-version 2.0 --region $AWS_REGION --query IntegrationId --output text)

aws apigatewayv2 create-route --api-id $API_ID --route-key "POST /process" --target integrations/$PROC_INT --region $AWS_REGION
aws apigatewayv2 create-route --api-id $API_ID --route-key "POST /approve" --target integrations/$APPR_INT --region $AWS_REGION
aws apigatewayv2 create-route --api-id $API_ID --route-key "GET /audit" --target integrations/$AUD_INT --region $AWS_REGION

aws apigatewayv2 create-stage --api-id $API_ID --stage-name $STAGE --auto-deploy --region $AWS_REGION

API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE}"

echo "Deploying Frontend..."
sed -i "s|https://YOUR_API_GATEWAY_URL|${API_URL}|g" frontend/index.html
aws s3 cp frontend/index.html s3://${S3_FRONTEND_BUCKET}/index.html --content-type text/html

FRONTEND_URL="http://${S3_FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"

echo "Deployment Complete"
echo "Frontend: $FRONTEND_URL"
echo "API: $API_URL"
