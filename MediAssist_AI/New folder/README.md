## AI Healthcare Workflow Support Prototype

**Goal**: An open-source, AWS-backed prototype that helps healthcare professionals work with **synthetic** or public clinical / research documents by:
- Generating concise professional summaries
- Highlighting key findings with confidence indicators
- Producing patient-friendly explanations for review

### High-level architecture

- **Frontend (React + Vite)** in `frontend`  
  - Single-page UI with tabs for Analyze, Patient View, and History  
  - Upload / paste synthetic clinical or research text  
  - Calls backend `/api/analyze` and visualizes summaries, confidence, and safety flags

- **Backend (Node.js)** in `backend`  
  - Express server for local development (`npm run start:local`)  
  - Lambda handler for production (`src/handlers/analyzeDocument.js`)  
  - Uses Amazon Bedrock (e.g. Claude 3 Haiku) for summarization and patient explanations

- **Infrastructure (AWS SAM)** in `infra`  
  - `template.yaml` defines a single Lambda + HTTP API  
  - Minimal permissions – only `bedrock:InvokeModel`

### Running locally

1. **Backend**
   - `cd backend`
   - `npm install`
   - Set AWS credentials and region that can invoke Bedrock (or configure a mock if desired)
   - `npm run start:local` (listens on `http://localhost:4000`)

2. **Frontend**
   - `cd frontend`
   - `npm install`
   - Create `.env` with `VITE_API_BASE_URL=http://localhost:4000`
   - `npm run dev` and open the printed URL

### Deploying to AWS (cost-aware)

- Use the SAM template in `infra/template.yaml`:
  - From `infra/`, run `sam build` then `sam deploy --guided`
  - Choose a **small Bedrock model** (e.g. Claude 3 Haiku) and a single region
  - Set a low concurrency limit on the Lambda and enable CloudWatch logs for auditability

This prototype is **synthetic-data only**, does **not** provide diagnosis or treatment advice, and is designed to be extended while staying open-source friendly.
