#!/bin/bash

# ================================================
# MediAssist AI — CloudWatch Dashboard Setup
# ================================================

AWS_REGION="ap-south-1"
DASHBOARD_NAME="MediAssist-AI-Dashboard"

echo "================================================"
echo " MediAssist AI — CloudWatch Dashboard Setup"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="$SCRIPT_DIR/dashboard.json"

if [ ! -f "$JSON_FILE" ]; then
  echo "ERROR: dashboard.json not found at $JSON_FILE"
  exit 1
fi

echo "Using: $JSON_FILE"

# ✅ Fix: use $(cat) instead of file:// — works on Windows Git Bash
aws cloudwatch put-dashboard \
  --dashboard-name "$DASHBOARD_NAME" \
  --region "$AWS_REGION" \
  --dashboard-body "$(cat "$JSON_FILE")"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Dashboard created!"
  echo ""
  echo "Open here:"
  echo "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
  echo ""
  echo "Live log commands:"
  echo "  aws logs tail /aws/lambda/MediAssist-Worker  --follow --region ${AWS_REGION} --format short"
  echo "  aws logs tail /aws/lambda/MediAssist-Process --follow --region ${AWS_REGION} --format short"
  echo "  aws logs tail /aws/lambda/MediAssist-Status  --follow --region ${AWS_REGION} --format short"
else
  echo "ERROR: Dashboard creation failed."
fi