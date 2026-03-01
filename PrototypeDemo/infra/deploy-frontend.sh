#!/bin/bash
set -e

source ../deployment-config.txt

echo "Creating React ENV..."

cat > ../frontend/.env.production <<EOF
REACT_APP_BASE_URL=$API_URL
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

echo "Frontend Updated 🚀"