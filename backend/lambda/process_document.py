"""
Lambda Function: process_document
Handles: Document text → Amazon Bedrock (Claude 3 Haiku) → Structured JSON response
Part of: MediAssist AI — AI for Bharat Hackathon (Team Cyber Scorpion)
"""

import json
import boto3
import logging
import re
import uuid
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')
dynamodb = boto3.resource('dynamodb')

# DynamoDB table names (set via Lambda environment variables)
import os
AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')
RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')

# Bedrock model
MODEL_ID = 'anthropic.claude-3-haiku-20240307-v1:0'


def lambda_handler(event, context):
    """Main Lambda handler — called by API Gateway"""
    
    # CORS headers for frontend
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
        'Content-Type': 'application/json'
    }
    
    # Handle CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        document_text = body.get('text', '').strip()
        filename = body.get('filename', 'unknown.pdf')
        
        if not document_text:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'No document text provided'})
            }
        
        # Safety: limit input size
        document_text = document_text[:8000]
        
        # Generate unique document ID
        doc_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        
        # Log upload event
        log_audit_event(
            doc_id=doc_id,
            event_type='UPLOAD',
            detail=f'Document received: {filename}',
            timestamp=timestamp
        )
        
        # Safety & compliance pre-check
        safety_result = safety_check(document_text)
        if not safety_result['safe']:
            log_audit_event(doc_id, 'SAFETY_BLOCK', f'Content blocked: {safety_result["reason"]}', timestamp)
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': f'Content safety check failed: {safety_result["reason"]}'})
            }
        
        log_audit_event(doc_id, 'SAFETY_PASS', 'Safety and compliance checks passed', timestamp)
        
        # Invoke Amazon Bedrock
        ai_result = invoke_bedrock(document_text, doc_id)
        
        # Store result in DynamoDB
        store_result(doc_id, filename, ai_result, timestamp)
        
        log_audit_event(doc_id, 'GENERATE', f'AI summary generated. Confidence: {ai_result["confidence_score"]}/100', timestamp)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'doc_id': doc_id,
                'professional_summary': ai_result['professional_summary'],
                'patient_explanation': ai_result['patient_explanation'],
                'confidence_score': ai_result['confidence_score'],
                'disclaimer': ai_result['disclaimer'],
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        logger.error(f'Error processing document: {str(e)}')
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Internal server error. Please try again.'})
        }


def safety_check(text):
    """
    Basic safety and compliance check before sending to Bedrock.
    In production, expand with Amazon Comprehend PII detection.
    """
    # Check for obvious PII patterns (basic)
    pii_patterns = [
        r'\b\d{3}-\d{2}-\d{4}\b',          # SSN
        r'\b\d{10,16}\b',                    # Credit card / long numbers  
        r'patient\s+id\s*:\s*[A-Z0-9]+',    # Patient IDs
    ]
    
    text_lower = text.lower()
    
    # Flag if it looks like real patient records
    real_patient_keywords = ['patient name:', 'dob:', 'date of birth:', 'mrn:', 'medical record number:']
    for kw in real_patient_keywords:
        if kw in text_lower:
            return {'safe': False, 'reason': 'Potential real patient data detected. Only synthetic/public documents allowed.'}
    
    return {'safe': True, 'reason': None}


def invoke_bedrock(document_text, doc_id):
    """
    Call Amazon Bedrock with Claude 3 Haiku to generate structured healthcare summary.
    """
    
    prompt = f"""You are a healthcare AI assistant that helps summarize clinical and research documents for healthcare professionals.

IMPORTANT RULES:
- Never make diagnoses or treatment recommendations
- Always note uncertainty with phrases like "the document states" or "according to the document"
- Provide a confidence score based on document clarity (0-100)
- Keep patient explanations in plain language (Grade 8 reading level)

DOCUMENT TO SUMMARIZE:
{document_text}

Respond ONLY with a valid JSON object (no markdown, no extra text):
{{
  "professional_summary": "Concise 2-4 sentence clinical summary for healthcare professionals, citing key findings, medications, values, and recommended actions from the document.",
  "patient_explanation": "Plain language 2-4 sentence explanation for patients. Avoid medical jargon. Focus on what this means for their health and what happens next.",
  "confidence_score": <integer 0-100 based on document clarity and completeness>,
  "disclaimer": "This AI-generated summary is based on the uploaded document and requires professional review. It is not a diagnostic tool and should not replace clinical judgment."
}}"""

    try:
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1024,
                'messages': [{'role': 'user', 'content': prompt}]
            }),
            contentType='application/json',
            accept='application/json'
        )
        
        response_body = json.loads(response['body'].read())
        content = response_body['content'][0]['text']
        
        # Parse JSON from response
        result = json.loads(content)
        
        # Validate required fields
        required = ['professional_summary', 'patient_explanation', 'confidence_score', 'disclaimer']
        for field in required:
            if field not in result:
                raise ValueError(f'Missing field: {field}')
        
        # Clamp confidence score
        result['confidence_score'] = max(0, min(100, int(result['confidence_score'])))
        
        return result
        
    except (json.JSONDecodeError, KeyError, ValueError) as e:
        logger.error(f'Bedrock response parsing error: {e}')
        # Return safe fallback
        return {
            'professional_summary': 'Document processed. AI was unable to generate a structured summary. Please review the original document directly.',
            'patient_explanation': 'Your healthcare provider will review this document and explain the key points to you.',
            'confidence_score': 20,
            'disclaimer': 'AI processing encountered an issue. This output requires thorough professional review before any use.'
        }


def store_result(doc_id, filename, result, timestamp):
    """Store AI result in DynamoDB for audit and retrieval"""
    try:
        table = dynamodb.Table(RESULTS_TABLE)
        table.put_item(Item={
            'doc_id': doc_id,
            'filename': filename,
            'timestamp': timestamp,
            'professional_summary': result['professional_summary'],
            'patient_explanation': result['patient_explanation'],
            'confidence_score': result['confidence_score'],
            'disclaimer': result['disclaimer'],
            'status': 'PENDING_REVIEW',
            'ttl': int(datetime.now(timezone.utc).timestamp()) + (7 * 24 * 3600)  # 7 day TTL
        })
    except Exception as e:
        logger.warning(f'DynamoDB store failed (non-critical): {e}')


def log_audit_event(doc_id, event_type, detail, timestamp=None):
    """Log an event to the audit trail in DynamoDB"""
    if timestamp is None:
        timestamp = datetime.now(timezone.utc).isoformat()
    
    try:
        table = dynamodb.Table(AUDIT_TABLE)
        table.put_item(Item={
            'event_id': str(uuid.uuid4()),
            'doc_id': doc_id,
            'event_type': event_type,
            'detail': detail,
            'timestamp': timestamp,
            'ttl': int(datetime.now(timezone.utc).timestamp()) + (30 * 24 * 3600)  # 30 day TTL
        })
    except Exception as e:
        logger.warning(f'Audit log write failed (non-critical): {e}')
