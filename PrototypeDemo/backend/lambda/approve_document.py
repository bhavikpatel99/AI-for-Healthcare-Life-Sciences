import os
import json
import boto3
import logging
import uuid
from datetime import datetime, timezone

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')
RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')

def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Content-Type': 'application/json'
    }

    if not LOCAL and event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        body = event if LOCAL else json.loads(event.get('body', '{}'))

        doc_id = body.get('doc_id')
        reviewer_id = body.get('reviewer_id', 'demo_user')
        edited_summary = body.get('edited_summary', '')
        edited_patient = body.get('edited_patient', '')

        if not doc_id:
            return response(400, {"error": "doc_id required"}, headers)

        table = dynamodb.Table(RESULTS_TABLE)

        table.update_item(
            Key={'doc_id': doc_id},
            UpdateExpression='SET #s = :s, approved_by = :r, edited_summary = :es, edited_patient = :ep',
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues={
                ':s': 'APPROVED',
                ':r': reviewer_id,
                ':es': edited_summary,
                ':ep': edited_patient
            }
        )

        log_audit(doc_id, "APPROVE", f"Approved by {reviewer_id}")

        return response(200, {"success": True}, headers)

    except Exception as e:
        logger.error(str(e))
        return response(500, {"error": "Approval failed"}, headers)


def log_audit(doc_id, event_type, detail):

    table = dynamodb.Table(AUDIT_TABLE)

    table.put_item(Item={
        "event_id": str(uuid.uuid4()),
        "doc_id": doc_id,
        "event_type": event_type,
        "detail": detail,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })


def response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers': headers,
        'body': json.dumps(body)
    }