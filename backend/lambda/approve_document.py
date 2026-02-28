"""
Lambda Function: approve_document
Handles: Human approval of AI-generated summaries + DynamoDB update
Part of: MediAssist AI — AI for Bharat Hackathon (Team Cyber Scorpion)
"""

import json
import boto3
import logging
import uuid
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')

import os
AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')
RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')


def lambda_handler(event, context):
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Content-Type': 'application/json'
    }
    
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}
    
    try:
        body = json.loads(event.get('body', '{}'))
        doc_id = body.get('doc_id')
        reviewer_id = body.get('reviewer_id', 'anonymous')
        edited_summary = body.get('edited_summary', '')
        edited_patient = body.get('edited_patient', '')
        
        if not doc_id:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'doc_id required'})
            }
        
        timestamp = datetime.now(timezone.utc).isoformat()
        
        # Update result record in DynamoDB
        table = dynamodb.Table(RESULTS_TABLE)
        table.update_item(
            Key={'doc_id': doc_id},
            UpdateExpression='SET #status = :status, approved_by = :reviewer, approved_at = :ts, edited_summary = :es, edited_patient = :ep',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': 'APPROVED',
                ':reviewer': reviewer_id,
                ':ts': timestamp,
                ':es': edited_summary,
                ':ep': edited_patient
            }
        )
        
        # Log approval to audit trail
        audit_table = dynamodb.Table(AUDIT_TABLE)
        audit_table.put_item(Item={
            'event_id': str(uuid.uuid4()),
            'doc_id': doc_id,
            'event_type': 'APPROVE',
            'detail': f'Document approved by reviewer: {reviewer_id}',
            'timestamp': timestamp,
            'ttl': int(datetime.now(timezone.utc).timestamp()) + (30 * 24 * 3600)
        })
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'success': True,
                'doc_id': doc_id,
                'approved_at': timestamp,
                'message': 'Document approved. Patient explanation released.'
            })
        }
        
    except Exception as e:
        logger.error(f'Approval error: {e}')
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Approval failed. Please try again.'})
        }
