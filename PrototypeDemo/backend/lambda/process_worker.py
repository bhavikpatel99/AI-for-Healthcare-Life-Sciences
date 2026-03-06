import os
import json
import boto3
import logging
import uuid
import urllib.request
import urllib.error
import re
from datetime import datetime, timezone

# This Lambda is called ASYNC by process_document.py
# It has no API Gateway timeout — can run up to 15 minutes
# It calls Ollama and stores result in DynamoDB when done

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'ap-south-1'))

AUDIT_TABLE     = os.environ.get('AUDIT_TABLE',     'MediAssist-AuditLog')
RESULTS_TABLE   = os.environ.get('RESULTS_TABLE',   'MediAssist-Results')
OLLAMA_ENDPOINT = os.environ.get('OLLAMA_ENDPOINT', 'http://3.109.55.138:11434')
OLLAMA_MODEL    = os.environ.get('OLLAMA_MODEL',    'llama3.2:3b')


# ------------------------------------------------
# WORKER HANDLER — no API GW timeout, runs in background
# ------------------------------------------------

def lambda_handler(event, context):

    doc_id        = event.get('doc_id')
    filename      = event.get('filename', 'unknown')
    s3_key        = event.get('s3_key', '')
    document_text = event.get('document_text', '')

    logger.info(f"Worker started for doc_id={doc_id}")

    try:
        # Call Ollama — takes as long as needed, no timeout issue
        ai_result = invoke_ollama(document_text)

        # Save result to DynamoDB — update status to PENDING (ready for review)
        store_result(doc_id, filename, ai_result, s3_key)
        log_audit(doc_id, 'GENERATE', 'AI summary generated via Ollama')

        logger.info(f"Worker completed for doc_id={doc_id}")

    except Exception as e:
        logger.error(f"Worker ERROR for doc_id={doc_id}: {str(e)}", exc_info=True)

        # Save FAILED status so frontend stops polling
        mark_failed(doc_id, str(e))
        log_audit(doc_id, 'ERROR', f'Processing failed: {str(e)}')


# ------------------------------------------------
# OLLAMA
# ------------------------------------------------

def invoke_ollama(text):
    prompt = """You are a clinical document summarizer for healthcare professionals.

Analyze the document below and return ONLY a valid JSON object with exactly these 4 fields:
{
  "professional_summary": "A concise clinical summary for the doctor (2-3 sentences)",
  "patient_explanation": "A simple, friendly explanation for the patient (2-3 sentences, no jargon)",
  "confidence_score": "High / Medium / Low",
  "disclaimer": "AI-generated summary. Must be reviewed and approved by a qualified healthcare professional before use."
}

Do NOT include any text before or after the JSON.

Document:
""" + text[:5000]

    payload = json.dumps({
        'model':  OLLAMA_MODEL,
        'prompt': prompt,
        'stream': False,
        'options': {
            'temperature': 0.1,
            'num_predict': 512
        }
    }).encode('utf-8')

    req = urllib.request.Request(
        f'{OLLAMA_ENDPOINT}/api/generate',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )

    try:
        # 10 minute timeout — worker has no API GW limit
        with urllib.request.urlopen(req, timeout=600) as resp:
            raw = json.loads(resp.read())
    except urllib.error.URLError as e:
        raise Exception(f'Cannot reach Ollama at {OLLAMA_ENDPOINT} — {str(e)}')

    content = raw.get('response', '').strip()
    logger.info(f'Ollama response (first 300): {content[:300]}')

    # Strip markdown fences
    if '```' in content:
        content = re.sub(r'```json\s*', '', content)
        content = re.sub(r'```\s*',     '', content)
        content = content.strip()

    try:
        result = json.loads(content)
    except json.JSONDecodeError:
        logger.warning(f'Ollama non-JSON response: {content[:200]}')
        result = {
            'professional_summary': content[:500] if content else 'Summary unavailable',
            'patient_explanation':  'Please ask your doctor to explain this document.',
            'confidence_score':     'Low',
            'disclaimer':           'AI-generated. Requires professional review.'
        }

    result.setdefault('professional_summary', 'Not available')
    result.setdefault('patient_explanation',  'Not available')
    result.setdefault('confidence_score',     'Low')
    result.setdefault('disclaimer',           'AI-generated. Requires professional review.')

    return result


# ------------------------------------------------
# DynamoDB
# ------------------------------------------------

def store_result(doc_id, filename, result, s3_key):
    table = dynamodb.Table(RESULTS_TABLE)
    table.update_item(
        Key={'doc_id': doc_id},
        UpdateExpression='''SET #s = :s,
                                professional_summary = :ps,
                                patient_explanation  = :pe,
                                confidence_score     = :cs,
                                disclaimer           = :d,
                                completed_at         = :t''',
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':s':  'PENDING',     # Ready for human review
            ':ps': result['professional_summary'],
            ':pe': result['patient_explanation'],
            ':cs': result['confidence_score'],
            ':d':  result['disclaimer'],
            ':t':  datetime.now(timezone.utc).isoformat()
        }
    )


def mark_failed(doc_id, error_msg):
    table = dynamodb.Table(RESULTS_TABLE)
    table.update_item(
        Key={'doc_id': doc_id},
        UpdateExpression='SET #s = :s, error_msg = :e',
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={
            ':s': 'FAILED',
            ':e': error_msg[:500]
        }
    )


def log_audit(doc_id, event_type, detail):
    table = dynamodb.Table(AUDIT_TABLE)
    table.put_item(Item={
        'event_id':   str(uuid.uuid4()),
        'doc_id':     doc_id,
        'event_type': event_type,
        'detail':     detail,
        'timestamp':  datetime.now(timezone.utc).isoformat()
    })