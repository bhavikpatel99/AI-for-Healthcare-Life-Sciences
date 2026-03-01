import os
import json
import boto3
import logging
import uuid
from datetime import datetime, timezone

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
s3 = boto3.client('s3', region_name='us-east-1')

AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'MediAssist-AuditLog')
RESULTS_TABLE = os.environ.get('RESULTS_TABLE', 'MediAssist-Results')
S3_BUCKET = os.environ.get('S3_BUCKET', 'mediassist-documents')

MODEL_ID = 'anthropic.claude-3-haiku-20240307-v1:0'


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

        document_text = body.get('text', '')[:8000]
        filename = body.get('filename', 'unknown')

        if not document_text:
            return response(400, {"error": "No document text"}, headers)

        doc_id = str(uuid.uuid4())

        s3_key = upload_to_s3(doc_id, document_text, filename)
        log_audit(doc_id, "S3_UPLOAD", f"Stored in S3: {s3_key}")

        ai_result = invoke_bedrock(document_text)

        store_result(doc_id, filename, ai_result, s3_key)
        log_audit(doc_id, "GENERATE", "AI summary generated")

        return response(200, {
            "doc_id": doc_id,
            **ai_result
        }, headers)

    except Exception as e:
        logger.error(str(e))
        return response(500, {"error": "Processing failed"}, headers)


def upload_to_s3(doc_id, text, filename):

    key = f"uploads/{doc_id}_{filename}.txt"

    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=text.encode("utf-8"),
        ContentType="text/plain"
    )

    return key


def invoke_bedrock(text):

    prompt = f"""
Summarize this clinical document.

Return ONLY JSON:
professional_summary
patient_explanation
confidence_score
disclaimer

{text}
"""

    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1024,
            "messages": [{"role": "user", "content": prompt}]
        }),
        contentType="application/json",
        accept="application/json"
    )

    result = json.loads(response['body'].read())
    content = result['content'][0]['text']

    return json.loads(content)


def store_result(doc_id, filename, result, s3_key):

    table = dynamodb.Table(RESULTS_TABLE)

    table.put_item(Item={
        "doc_id": doc_id,
        "filename": filename,
        "s3_key": s3_key,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "professional_summary": result["professional_summary"],
        "patient_explanation": result["patient_explanation"],
        "confidence_score": result["confidence_score"],
        "disclaimer": result["disclaimer"],
        "status": "PENDING"
    })


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