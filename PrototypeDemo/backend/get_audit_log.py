import os
import json
import boto3
import logging

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')

def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,GET',
        'Content-Type': 'application/json'
    }

    if not LOCAL and event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        params = event if LOCAL else event.get('queryStringParameters') or {}
        doc_id = params.get('doc_id')

        if not doc_id:
            return response(400, {"error": "doc_id required"}, headers)

        table = dynamodb.Table(AUDIT_TABLE)
        response_db = table.scan()

        items = [i for i in response_db.get('Items', []) if i.get('doc_id') == doc_id]

        return response(200, items, headers)

    except Exception as e:
        logger.error(str(e))
        return response(500, {"error": "Failed to fetch audit log"}, headers)


def response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers': headers,
        'body': json.dumps(body)
    }