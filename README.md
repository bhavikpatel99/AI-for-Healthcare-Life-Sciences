# 🏥 MediAssist AI — Healthcare Workflow Support System

> **AI for Bharat Hackathon 2026** | Team Cyber Scorpion | Healthcare & Life Sciences Track

An AI-powered clinical document processing system that generates professional summaries and patient-friendly explanations — with full human-in-the-loop approval workflow.

> ⚠️ **This system uses only synthetic data and is for demonstration purposes only. It does not provide medical diagnoses or treatment recommendations.**

---

## 🎯 Problem Statement

Healthcare professionals spend significant time summarizing complex clinical documents for patients. MediAssist AI automates this using local LLM inference — keeping data secure, reducing clinician workload, and improving patient understanding.

---

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌──────────────────────┐
│   React         │───▶│   API Gateway   │───▶│  MediAssist-Process  │ (30s)
│   Frontend      │    │   (HTTP API)    │    │  Lambda              │
└─────────────────┘    └─────────────────┘    └──────────┬───────────┘
        │                                                 │ async invoke
        │ polls /status every 5s                          ▼
        │                                     ┌──────────────────────┐
        │                                     │  MediAssist-Worker   │ (600s)
        │                                     │  Lambda + Ollama     │
        │                                     └──────────┬───────────┘
        │                                                 │
        ▼                                                 ▼
┌─────────────────┐          ┌─────────────────┐  ┌──────────────┐
│   DynamoDB      │◀─────────│   S3 Storage    │  │  Ollama LLM  │
│   (3 Tables)    │          │   (Documents)   │  │  EC2 t3.large│
└─────────────────┘          └─────────────────┘  └──────────────┘
```

### Why Async Pattern?
API Gateway has a hard **29-second timeout**. Ollama on EC2 takes **60-90 seconds**. Solution: `Process` Lambda returns `doc_id` instantly, `Worker` Lambda runs Ollama in the background, frontend polls `/status` every 5 seconds.

---

## ✨ Features

| Feature | Details |
|---------|---------|
| 📄 Multi-format upload | PDF, DOCX, TXT, JPG, PNG, TIFF, BMP, WebP |
| 🔍 OCR support | Amazon Textract for scanned PDFs and images |
| 🧠 AI summarization | llama3.2:3b via Ollama — professional + patient summaries |
| 👨‍⚕️ Human review | Doctor can edit and approve before release |
| 📋 Audit trail | Full compliance log for every action |
| 📊 Monitoring | CloudWatch dashboard for all Lambda functions |
| 🔒 Secure | IAM roles, S3 encryption, no real patient data |

---

## 🛠️ Technology Stack

**Frontend**
- React 19.2 + Vite
- TailwindCSS
- Polling-based status updates (no WebSocket needed)

**Backend**
- AWS Lambda (Python 3.11) — 5 functions
- Amazon API Gateway (HTTP API v2)
- Amazon DynamoDB (3 tables, PAY_PER_REQUEST)
- Amazon S3 (document + frontend hosting)
- Amazon Textract (OCR)
- Ollama + llama3.2:3b on EC2 t3.large

---

## 📁 Project Structure

```
.
├── PrototypeDemo/
│   ├── frontend/
│   │   └── src/
│   │       ├── panels/           # UploadPanel, ProcessingPanel, ReviewPanel, ExportPanel
│   │       ├── context/          # AppContext — global state
│   │       └── services/         # API calls
│   │
│   ├── backend/
│   │   └── lambda/
│   │       ├── process_document.py   # Receives upload, triggers Worker async
│   │       ├── process_worker.py     # Calls Ollama, updates DynamoDB
│   │       ├── get_status.py         # Polled by frontend every 5s
│   │       ├── approve_document.py   # Doctor approval workflow
│   │       └── get_audit_log.py      # Compliance audit trail
│   │
│   └── infra/
│       ├── deploy.sh             # Full deployment (S3 + DynamoDB + Lambda + API GW)
│       ├── dashboard.json        # CloudWatch dashboard config
│       └── setup_dashboard.sh    # Creates CloudWatch dashboard
│
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites
- Node.js 18+ and npm
- Python 3.11+
- AWS CLI configured (`aws configure`)
- AWS account with Lambda, S3, DynamoDB, API Gateway, Textract permissions

### Local Development

```bash
# 1. Install frontend dependencies
cd PrototypeDemo/frontend
npm install

# 2. Set environment variable
echo "VITE_API_BASE_URL=https://your-api-id.execute-api.ap-south-1.amazonaws.com/prod" > .env.local

# 3. Run dev server
npm run dev
# → http://localhost:5173
```

### Full AWS Deployment

```bash
cd PrototypeDemo/infra
bash deploy.sh
```

The script automatically:
1. ✅ Checks Ollama is reachable on EC2
2. ✅ Creates S3 buckets
3. ✅ Creates DynamoDB tables
4. ✅ Sets up IAM role + policies (S3, DynamoDB, Textract, Lambda invoke)
5. ✅ Packages and deploys all 5 Lambda functions
6. ✅ Configures API Gateway with CORS
7. ✅ Builds and deploys React frontend

### CloudWatch Dashboard

```bash
cd PrototypeDemo/infra
bash setup_dashboard.sh
```

---

## 📡 API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/process` | Upload document → returns `doc_id` instantly |
| `GET` | `/status?doc_id=xxx` | Poll for AI result (call every 5s) |
| `POST` | `/approve` | Doctor approves/edits summary |
| `GET` | `/audit?doc_id=xxx` | Get full audit trail |

### Example Flow

```bash
# 1. Upload document
curl -X POST https://API_URL/process \
  -F "file=@clinical_report.pdf"
# → { "doc_id": "abc-123", "status": "PROCESSING" }

# 2. Poll status (repeat until status != PROCESSING)
curl https://API_URL/status?doc_id=abc-123
# → { "status": "PENDING", "professional_summary": "...", "patient_explanation": "..." }

# 3. Approve
curl -X POST https://API_URL/approve \
  -H "Content-Type: application/json" \
  -d '{"doc_id": "abc-123", "reviewer_id": "dr_smith"}'
```

---

## ⚙️ Lambda Functions

| Function | Timeout | Memory | Purpose |
|----------|---------|--------|---------|
| MediAssist-Process | 30s | 512MB | Receives upload, triggers Worker async |
| MediAssist-Worker | 600s | 512MB | Runs Ollama — no API GW timeout limit |
| MediAssist-Status | 30s | 256MB | Polled by frontend every 5s |
| MediAssist-Approve | 30s | 256MB | Human review + edit |
| MediAssist-Audit | 30s | 256MB | Compliance log retrieval |

---

## 🔧 Environment Variables

All Lambda functions share these environment variables (set automatically by `deploy.sh`):

```
OLLAMA_ENDPOINT=http://<EC2_IP>:11434
OLLAMA_MODEL=llama3.2:3b
RESULTS_TABLE=MediAssist-Results
AUDIT_TABLE=MediAssist-AuditLog
DOCS_BUCKET=mediassistai-documents
WORKER_FUNCTION=MediAssist-Worker
```

---

## 🧹 Cleanup

```bash
cd PrototypeDemo/infra
bash cleanup.sh
```

Deletes all Lambda functions, API Gateway, DynamoDB tables, S3 buckets, and IAM roles.

---

## ⚠️ Limitations

- **No real patient data** — synthetic/demo data only
- **English only** — LLM optimised for English clinical text
- **Not for diagnosis** — AI outputs require professional validation
- **Demo scale** — not production-hardened

---

## 🤝 Responsible AI

- **Human oversight** — doctors review and approve every AI output before release
- **Transparency** — confidence scores shown for every summary
- **Safety constraints** — LLM prompt explicitly prevents diagnostic recommendations
- **Audit trail** — every action logged for compliance

---

## 👥 Team

**Team Cyber Scorpion** | AI for Bharat Hackathon 2026

| Role | Details |
|------|---------|
| Team Lead | Bhavik Patel |
| Track | Healthcare & Life Sciences |
| Hackathon | AI for Bharat (powered by AWS) |

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

**Version**: 1.0 | **Last Updated**: March 2026 | **Status**: Hackathon Prototype

> *MediAssist AI is a demonstration prototype. Always consult qualified healthcare professionals for medical decisions.*
