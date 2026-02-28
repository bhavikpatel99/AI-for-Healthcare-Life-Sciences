## AI Healthcare Workflow Support - Prototype Architecture

This prototype implements a thin, cost-aware slice of the architecture described in `requirements.md` and `design.md`.

### Frontend (React)

- Location: `frontend/`
- Tech: React + Vite, Axios
- Features:
  - **Analyze tab** – Paste or upload synthetic clinical / research text and request an AI summary
  - **Summary panel** – Professional summary, key findings, confidence indicators, and safety flags
  - **Patient View** – Patient-friendly explanation for review and editing
  - **History** – Local-only (browser) history of recent analyses
- Configuration:
  - `VITE_API_BASE_URL` points to local Express server or deployed API Gateway endpoint

### Backend (Node.js + Amazon Bedrock)

- Location: `backend/`
- Tech: Node.js, Express (for local dev), AWS SDK v3 for Bedrock
- Core flow:
  1. Receive JSON `{ text, audience }` over `/api/analyze`
  2. Build a safety-focused prompt covering:
     - Professional summary
     - Patient-friendly explanation
     - Confidence scores
     - Safety flags (no diagnosis / treatment, synthetic-only reminder)
  3. Call Amazon Bedrock (e.g. Claude 3 Haiku) via `@aws-sdk/client-bedrock-runtime`
  4. Parse the model JSON and return a normalized response to the frontend
- Safety & compliance:
  - Prompts explicitly forbid diagnosis and treatment recommendations
  - Responses carry safety flags field for UI highlighting
  - Logs (in Lambda / CloudWatch) provide an audit trail of activity (no PHI)

### Infrastructure (SAM / Lambda + HTTP API)

- Location: `infra/template.yaml`
- Components:
  - **Lambda function**: `AnalyzeDocumentFunction`
  - **HTTP API**: Minimal `/api/analyze` POST endpoint with CORS
- Environment:
  - `BEDROCK_MODEL_ID` and `BEDROCK_REGION` parameters
- Permissions:
  - `"bedrock:InvokeModel"` only, scoped for the chosen region / account

### Cost & Open-Source Considerations

- Single Lambda + single HTTPS endpoint keeps AWS footprint minimal
- Bedrock model choice (small model, low temperature, limited max tokens) controls spend
- No long-lived storage or databases required for the prototype path
- All code is framework-light and license-friendly for open-source hosting on GitHub

