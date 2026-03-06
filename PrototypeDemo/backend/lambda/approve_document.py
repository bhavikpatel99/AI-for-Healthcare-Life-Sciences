import os
import json
import boto3
import logging
import uuid
from datetime import datetime, timezone

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ✅ Fix 1: region from env var, not hardcoded us-east-1
dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'ap-south-1'))

AUDIT_TABLE   = os.environ.get('AUDIT_TABLE',   'MediAssist-AuditLog')
RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')


def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Content-Type': 'application/json'
    }

    # ✅ Fix 2: HTTP API Gateway v2 uses requestContext.http.method, not httpMethod
    if not LOCAL and event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        body = event if LOCAL else json.loads(event.get('body', '{}'))

        doc_id         = body.get('doc_id')
        reviewer_id    = body.get('reviewer_id', 'demo_user')
        edited_summary = body.get('edited_summary', '')
        edited_patient = body.get('edited_patient', '')

        if not doc_id:
            return build_response(400, {'error': 'doc_id required'}, headers)

        table = dynamodb.Table(RESULTS_TABLE)

        # ✅ Fix 3: added approved_at timestamp so you know when it was approved
        table.update_item(
            Key={'doc_id': doc_id},
            UpdateExpression='''SET #s = :s,
                                    approved_by = :r,
                                    approved_at = :t,
                                    edited_summary = :es,
                                    edited_patient = :ep''',
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues={
                ':s':  'APPROVED',
                ':r':  reviewer_id,
                ':t':  datetime.now(timezone.utc).isoformat(),
                ':es': edited_summary,
                ':ep': edited_patient
            }
        )

        log_audit(doc_id, 'APPROVE', f'Approved by {reviewer_id}')

        return build_response(200, {'success': True, 'doc_id': doc_id}, headers)

    except Exception as e:
        logger.error(f'Approval error: {str(e)}')
        return build_response(500, {'error': 'Approval failed'}, headers)


def log_audit(doc_id, event_type, detail):
    table = dynamodb.Table(AUDIT_TABLE)

    table.put_item(Item={
        'event_id':   str(uuid.uuid4()),
        'doc_id':     doc_id,
        'event_type': event_type,
        'detail':     detail,
        'timestamp':  datetime.now(timezone.utc).isoformat()
    })


def build_response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers':    headers,
        'body':       json.dumps(body)
    }