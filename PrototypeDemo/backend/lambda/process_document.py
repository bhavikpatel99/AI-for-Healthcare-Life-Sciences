import os
import json
import boto3
import logging
import uuid
import base64
import re
import io
from datetime import datetime, timezone

# ✅ PDF support
try:
    import PyPDF2
    PDF_SUPPORT = True
except ImportError:
    PDF_SUPPORT = False

# ✅ DOCX support
try:
    import docx
    DOCX_SUPPORT = True
except ImportError:
    DOCX_SUPPORT = False

LOCAL = False if "AWS_LAMBDA_FUNCTION_NAME" in os.environ else True

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb   = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'ap-south-1'))
s3         = boto3.client('s3',         region_name=os.environ.get('AWS_REGION', 'ap-south-1'))
lambda_cli = boto3.client('lambda',     region_name=os.environ.get('AWS_REGION', 'ap-south-1'))
textract   = boto3.client('textract',   region_name=os.environ.get('AWS_REGION', 'ap-south-1'))

AUDIT_TABLE     = os.environ.get('AUDIT_TABLE',     'MediAssist-AuditLog')
RESULTS_TABLE   = os.environ.get('RESULTS_TABLE',   'MediAssist-Results')
S3_BUCKET       = os.environ.get('DOCS_BUCKET',     'mediassistai-documents')
WORKER_FUNCTION = os.environ.get('WORKER_FUNCTION', 'MediAssist-Worker')

# Supported image types
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.tiff', '.tif', '.bmp', '.webp'}
IMAGE_MIME_TYPES  = {'image/jpeg', 'image/png', 'image/tiff', 'image/bmp', 'image/webp'}


# ------------------------------------------------
# MAIN HANDLER — returns doc_id instantly (<1s)
# ------------------------------------------------

def lambda_handler(event, context):

    headers = {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Content-Type': 'application/json'
    }

    if not LOCAL and event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:

        # --------- INPUT HANDLING ---------
        if LOCAL:
            body          = event
            document_text = body.get('text', '')[:8000]
            filename      = body.get('filename', 'unknown')
        else:
            content_type = (
                event.get('headers', {}).get('content-type') or
                event.get('headers', {}).get('Content-Type', '')
            )
            logger.info(f"Content-Type: {content_type}")

            if content_type and 'multipart/form-data' in content_type:
                document_text, filename = parse_multipart(
                    event['body'],
                    content_type,
                    event.get('isBase64Encoded', False)
                )
            else:
                raw_body      = event.get('body', '{}') or '{}'
                body          = json.loads(raw_body)
                document_text = body.get('text', '')[:8000]
                filename      = body.get('filename', 'unknown')

        if not document_text.strip():
            return build_response(400, {'error': 'No text could be extracted from the uploaded file'}, headers)

        logger.info(f"Extracted {len(document_text)} chars from {filename}")

        # --------- SAVE TO S3 + DYNAMO ---------
        doc_id = str(uuid.uuid4())
        s3_key = upload_to_s3(doc_id, document_text, filename)

        save_pending(doc_id, filename, s3_key)
        log_audit(doc_id, 'RECEIVED', f'Document received: {filename}')

        # --------- TRIGGER WORKER ASYNC ---------
        lambda_cli.invoke(
            FunctionName=WORKER_FUNCTION,
            InvocationType='Event',
            Payload=json.dumps({
                'doc_id':        doc_id,
                'filename':      filename,
                's3_key':        s3_key,
                'document_text': document_text
            }).encode('utf-8')
        )

        logger.info(f"Worker triggered async for doc_id={doc_id}")

        return build_response(202, {
            'doc_id':  doc_id,
            'status':  'PROCESSING',
            'message': 'Document received. Poll /status?doc_id=' + doc_id
        }, headers)

    except Exception as e:
        logger.error(f'ERROR: {str(e)}', exc_info=True)
        return build_response(500, {'error': str(e)}, headers)


# ------------------------------------------------
# PDF extraction — PyPDF2
# ------------------------------------------------

def extract_pdf_text(file_bytes):
    if not PDF_SUPPORT:
        raise ValueError("PyPDF2 not installed")

    reader    = PyPDF2.PdfReader(io.BytesIO(file_bytes))
    text_parts = []

    logger.info(f"PDF has {len(reader.pages)} pages")
    for i, page in enumerate(reader.pages):
        try:
            t = page.extract_text()
            if t:
                text_parts.append(t)
        except Exception as e:
            logger.warning(f"Skipping page {i}: {e}")

    full_text = "\n".join(text_parts).strip()

    if not full_text:
        # Scanned PDF — fall back to Textract
        logger.info("PDF has no text layer — falling back to Textract OCR")
        return extract_image_text_textract(file_bytes)

    return full_text[:8000]


# ------------------------------------------------
# Image OCR — Amazon Textract
# ------------------------------------------------

def extract_image_text_textract(file_bytes):
    """Use Amazon Textract to OCR images and scanned PDFs."""
    logger.info(f"Calling Textract on {len(file_bytes)} bytes")

    response = textract.detect_document_text(
        Document={'Bytes': file_bytes}
    )

    lines = [
        block['Text']
        for block in response.get('Blocks', [])
        if block['BlockType'] == 'LINE'
    ]

    full_text = "\n".join(lines).strip()

    if not full_text:
        raise ValueError(
            "No text could be detected in this image. "
            "Please ensure the image is clear and contains readable text."
        )

    logger.info(f"Textract extracted {len(full_text)} chars")
    return full_text[:8000]


# ------------------------------------------------
# DOCX extraction — python-docx
# ------------------------------------------------

def extract_docx_text(file_bytes):
    if DOCX_SUPPORT:
        doc        = docx.Document(io.BytesIO(file_bytes))
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        full_text  = "\n".join(paragraphs).strip()
        if full_text:
            return full_text[:8000]

    # Fallback: regex on XML content
    logger.warning("python-docx not available, using XML fallback")
    raw          = file_bytes.decode('utf-8', errors='ignore')
    text_matches = re.findall(r'<w:t[^>]*>([^<]+)</w:t>', raw)
    return ' '.join(text_matches)[:8000]


# ------------------------------------------------
# Multipart parser — routes by file type
# ------------------------------------------------

def parse_multipart(body_raw, content_type, is_base64):
    if is_base64:
        body_bytes = base64.b64decode(body_raw)
    else:
        body_bytes = body_raw.encode('utf-8') if isinstance(body_raw, str) else body_raw

    boundary_match = re.search(r'boundary=([^\s;]+)', content_type)
    if not boundary_match:
        raise ValueError(f'Cannot find boundary in Content-Type: {content_type}')

    boundary  = boundary_match.group(1).strip('"')
    delimiter = f'--{boundary}'.encode()
    parts     = body_bytes.split(delimiter)

    filename      = 'unknown'
    document_text = ''

    for part in parts:
        if b'Content-Disposition' not in part:
            continue

        if b'\r\n\r\n' in part:
            header_section, file_body = part.split(b'\r\n\r\n', 1)
        elif b'\n\n' in part:
            header_section, file_body = part.split(b'\n\n', 1)
        else:
            continue

        headers_text = header_section.decode('utf-8', errors='ignore')
        if 'name="file"' not in headers_text:
            continue

        fn_match = re.search(r'filename="([^"]+)"', headers_text)
        if fn_match:
            filename = fn_match.group(1)

        file_body = file_body.rstrip(b'\r\n--')
        ext       = os.path.splitext(filename.lower())[1]

        logger.info(f"Processing file: {filename} (ext={ext}, size={len(file_body)} bytes)")

        # ✅ Route to correct extractor
        if ext == '.pdf':
            document_text = extract_pdf_text(file_body)

        elif ext == '.docx':
            document_text = extract_docx_text(file_body)

        elif ext in IMAGE_EXTENSIONS:
            document_text = extract_image_text_textract(file_body)

        elif ext == '.txt':
            document_text = file_body.decode('utf-8', errors='ignore')[:8000]

        else:
            # Unknown type — try plain text, fall back to Textract
            try:
                document_text = file_body.decode('utf-8', errors='ignore')[:8000]
                if not document_text.strip():
                    raise ValueError("Empty text")
            except Exception:
                document_text = extract_image_text_textract(file_body)

        break

    if not document_text.strip():
        raise ValueError('No text content could be extracted from the uploaded file')

    return document_text, filename


# ------------------------------------------------
# S3
# ------------------------------------------------

def upload_to_s3(doc_id, text, filename):
    key = f'uploads/{doc_id}_{filename}.txt'
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=text.encode('utf-8'),
        ContentType='text/plain'
    )
    return key


# ------------------------------------------------
# DynamoDB
# ------------------------------------------------

def save_pending(doc_id, filename, s3_key):
    table = dynamodb.Table(RESULTS_TABLE)
    table.put_item(Item={
        'doc_id':    doc_id,
        'filename':  filename,
        's3_key':    s3_key,
        'status':    'PROCESSING',
        'timestamp': datetime.now(timezone.utc).isoformat()
    })


def log_audit(doc_id, event_type, detail):
    table = dynamodb.Table(AUDIT_TABLE)
    table.put_item(Item={
        'event_id':   str(uuid.uuid4()),
        'doc_id':     doc_id,
        'event_type': event_type,
        'detail':     detail,
        'timestamp':  datetime.now(timezone.utc).isoformat()
    })


# ------------------------------------------------
# Response
# ------------------------------------------------

def build_response(code, body, headers):
    if LOCAL:
        return body
    return {
        'statusCode': code,
        'headers':    headers,
        'body':       json.dumps(body)
    }