# MediAssist AI — Architecture Deep Dive

## AWS Architecture Overview

### Layer 1: Input & Access Layer
- **Amazon S3 (Frontend)**: Static website hosting for the single-page app
- **Amazon API Gateway (HTTP API)**: Two routes — `/process` and `/approve`
- Authentication: Currently open (add Amazon Cognito for production)

### Layer 2: Preprocessing & Validation Layer
- **Lambda: process_document.py**
  - Validates file type and size
  - Runs safety checks for potential PHI patterns
  - Truncates input to safe length (8000 chars)
  - Logs all events to CloudWatch

### Layer 3: AI Processing Layer
- **Amazon Bedrock — Claude 3 Haiku**
  - Model ID: `anthropic.claude-3-haiku-20240307-v1:0`
  - Structured prompt forces JSON output with 4 required fields
  - Max tokens: 1024
  - Has fallback response if parsing fails

### Layer 4: Human Review Layer
- **Lambda: approve_document.py**
  - Validates doc_id exists
  - Updates DynamoDB record status to APPROVED
  - Logs approval event with timestamp and reviewer info
  - Patient explanation is blocked until this step completes

### Layer 5: Output & Storage Layer
- **DynamoDB: MediAssist-Results**
  - Stores AI outputs with 7-day TTL
  - Updated on approval with edited content
- **DynamoDB: MediAssist-AuditLog**
  - Event types: UPLOAD, SAFETY_PASS, GENERATE, EDIT, APPROVE, EXPORT
  - 30-day TTL
  - Append-only design

---

## Bedrock Prompt Template

```
You are a healthcare AI assistant that helps summarize clinical and research documents for healthcare professionals.

IMPORTANT RULES:
- Never make diagnoses or treatment recommendations
- Always note uncertainty with phrases like "the document states" or "according to the document"
- Provide a confidence score based on document clarity (0-100)
- Keep patient explanations in plain language (Grade 8 reading level)

DOCUMENT TO SUMMARIZE:
{document_text}

Respond ONLY with a valid JSON object:
{
  "professional_summary": "...",
  "patient_explanation": "...",
  "confidence_score": <0-100>,
  "disclaimer": "..."
}
```

---

## DynamoDB Table Schemas

### MediAssist-Results
| Attribute | Type | Description |
|-----------|------|-------------|
| doc_id (PK) | String | UUID v4 |
| filename | String | Original filename |
| timestamp | String | ISO 8601 |
| professional_summary | String | AI-generated |
| patient_explanation | String | AI-generated |
| confidence_score | Number | 0-100 |
| disclaimer | String | AI-generated |
| status | String | PENDING_REVIEW / APPROVED |
| approved_by | String | Reviewer ID (on approval) |
| approved_at | String | ISO 8601 (on approval) |
| edited_summary | String | Post-edit content |
| ttl | Number | Unix timestamp for auto-delete |

### MediAssist-AuditLog
| Attribute | Type | Description |
|-----------|------|-------------|
| event_id (PK) | String | UUID v4 |
| doc_id | String | Reference to Results table |
| event_type | String | UPLOAD / SAFETY_PASS / GENERATE / EDIT / APPROVE / EXPORT |
| detail | String | Human-readable description |
| timestamp | String | ISO 8601 |
| ttl | Number | Unix timestamp for auto-delete |

---

## Security Considerations

1. **S3 Documents Bucket**: All public access blocked; only Lambda can read/write
2. **IAM Role**: Least-privilege — Lambda can only access specific Bedrock model, specific DynamoDB tables, specific S3 bucket
3. **No PHI**: Safety check runs before Bedrock invocation
4. **HTTPS**: API Gateway enforces TLS
5. **Input sanitization**: Text truncated to 8000 chars max
