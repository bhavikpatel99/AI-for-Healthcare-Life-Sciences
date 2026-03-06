import os
import json
import boto3
import logging
from datetime import datetime, timezone

# Frontend polls GET /status?doc_id=xxx every 3 seconds
# Returns PROCESSING, PENDING (ready), APPROVED, or FAILED

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'ap-south-1'))

RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')


def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,GET',
        'Content-Type': 'application/json'
    }

    if not LOCAL and event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        params = event if LOCAL else event.get('queryStringParameters') or {}
        doc_id = params.get('doc_id')

        if not doc_id:
            return build_response(400, {'error': 'doc_id required'}, headers)

        table  = dynamodb.Table(RESULTS_TABLE)
        result = table.get_item(Key={'doc_id': doc_id})
        item   = result.get('Item')

        if not item:
            return build_response(404, {'error': 'doc_id not found'}, headers)

        status = item.get('status', 'PROCESSING')

        if status == 'PROCESSING':
            # Still running — tell frontend to keep polling
            return build_response(200, {
                'doc_id':  doc_id,
                'status':  'PROCESSING',
                'message': 'Still processing, please wait...'
            }, headers)

        elif status == 'FAILED':
            return build_response(200, {
                'doc_id':  doc_id,
                'status':  'FAILED',
                'error':   item.get('error_msg', 'Unknown error')
            }, headers)

        else:
            # PENDING or APPROVED — return full result
            return build_response(200, {
                'doc_id':               doc_id,
                'status':               status,
                'professional_summary': item.get('professional_summary', ''),
                'patient_explanation':  item.get('patient_explanation', ''),
                'confidence_score':     item.get('confidence_score', ''),
                'disclaimer':           item.get('disclaimer', ''),
                'filename':             item.get('filename', ''),
                'timestamp':            item.get('timestamp', ''),
                'completed_at':         item.get('completed_at', '')
            }, headers)

    except Exception as e:
        logger.error(f'Status check error: {str(e)}')
        return build_response(500, {'error': str(e)}, headers)


def build_response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers':    headers,
        'body':       json.dumps(body)
    }