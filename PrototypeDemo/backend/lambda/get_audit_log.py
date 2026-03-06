import os
import json
import boto3
import logging
from boto3.dynamodb.conditions import Attr

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ✅ Fix 1: region from env var, not hardcoded us-east-1
dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'ap-south-1'))

AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')


def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,GET',
        'Content-Type': 'application/json'
    }

    # ✅ Fix 2: HTTP API Gateway v2 uses requestContext.http.method, not httpMethod
    if not LOCAL and event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        params = event if LOCAL else event.get('queryStringParameters') or {}
        doc_id = params.get('doc_id')

        if not doc_id:
            return build_response(400, {'error': 'doc_id required'}, headers)

        table = dynamodb.Table(AUDIT_TABLE)

        # ✅ Fix 3: Use scan with FilterExpression instead of scanning ALL records
        # and filtering in Python — much more efficient and won't break at scale
        result = table.scan(
            FilterExpression=Attr('doc_id').eq(doc_id)
        )

        items = result.get('Items', [])

        # Handle DynamoDB pagination — scan returns max 1MB per page
        while 'LastEvaluatedKey' in result:
            result = table.scan(
                FilterExpression=Attr('doc_id').eq(doc_id),
                ExclusiveStartKey=result['LastEvaluatedKey']
            )
            items.extend(result.get('Items', []))

        # Sort by timestamp so frontend gets events in order
        items.sort(key=lambda x: x.get('timestamp', ''))

        logger.info(f'Fetched {len(items)} audit events for doc_id={doc_id}')

        return build_response(200, items, headers)

    except Exception as e:
        logger.error(f'Audit fetch error: {str(e)}')
        return build_response(500, {'error': 'Failed to fetch audit log'}, headers)


def build_response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers':    headers,
        'body':       json.dumps(body)
    }