# MediAssist AI - Healthcare Workflow Support System

An AI-powered healthcare solution that processes synthetic clinical documents to generate professional summaries and patient-friendly explanations. Built with React, AWS Lambda, and Ollama LLM.

## Overview

MediAssist AI is a prototype demonstration of responsible AI in healthcare, designed to:

- Process clinical documents (PDF, DOCX, images, text) and extract medical information
- Generate professional clinical summaries for healthcare providers
- Create patient-friendly explanations of medical content
- Maintain comprehensive audit trails for compliance
- Support human-in-the-loop workflows with approval mechanisms

**Important**: This system uses only synthetic data and is designed for demonstration purposes. It does not provide medical diagnoses or treatment recommendations.

## Architecture

### System Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │───▶│   API Gateway   │───▶│  Lambda Layer   │
│   (React)       │    │   (HTTP API)    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                       ┌────────────────────────────────┼────────────────┐
                       ▼                                ▼                ▼
              ┌─────────────────┐          ┌─────────────────┐  ┌──────────────┐
              │   DynamoDB      │          │   S3 Storage    │  │   Ollama     │
              │   (3 Tables)    │          │   (Documents)   │  │   (EC2)      │
              └─────────────────┘          └─────────────────┘  └──────────────┘
```

### Technology Stack

**Frontend**
- React 19.2 with Vite
- Bootstrap 5.3 & AdminLTE 4.0
- Axios for API communication
- TailwindCSS for styling

**Backend**
- AWS Lambda (Python 3.11)
- Amazon API Gateway (HTTP API)
- Amazon DynamoDB (3 tables)
- Amazon S3 (document storage)
- Amazon Textract (OCR for images/scanned PDFs)
- Ollama LLM on EC2 (llama3.2:3b)

**Document Processing**
- PyPDF2 for PDF extraction
- python-docx for DOCX files
- Amazon Textract for image OCR

## Features

### Document Processing
- Multi-format support: PDF, DOCX, TXT, images (JPG, PNG, TIFF, BMP, WebP)
- OCR for scanned documents and images via Amazon Textract
- Async processing pattern (no API Gateway timeout issues)
- Real-time status polling

### AI Capabilities
- Clinical text summarization using Ollama LLM
- Patient-friendly explanation generation
- Confidence scoring for AI outputs
- Safety filters to prevent diagnostic/treatment recommendations

### Compliance & Audit
- Comprehensive audit logging for all operations
- Human-in-the-loop approval workflow
- HIPAA-aligned practices (even with synthetic data)
- Complete action trail for regulatory compliance

### User Interface
- Step-by-step workflow (Upload → Processing → Review → Export)
- Real-time processing status updates
- Professional dashboard for healthcare providers
- Responsive design for desktop and mobile

## Project Structure

```
.
├── PrototypeDemo/
│   ├── frontend/              # React application
│   │   ├── src/
│   │   │   ├── components/    # Reusable UI components
│   │   │   ├── panels/        # Step-based workflow panels
│   │   │   ├── context/       # React context for state management
│   │   │   └── services/      # API integration layer
│   │   ├── package.json
│   │   └── vite.config.js
│   │
│   ├── backend/
│   │   ├── lambda/            # AWS Lambda functions
│   │   │   ├── process_document.py    # Document upload handler
│   │   │   ├── process_worker.py      # AI processing worker
│   │   │   ├── get_status.py          # Status polling endpoint
│   │   │   ├── approve_document.py    # Approval workflow
│   │   │   └── get_audit_log.py       # Audit trail retrieval
│   │   └── requirements.txt
│   │
│   └── infra/                 # Infrastructure & deployment
│       ├── deploy.sh          # Main deployment script
│       ├── deploy-frontend.sh # Frontend-only deployment
│       ├── cleanup.sh         # Resource cleanup
│       └── dashboard.json     # CloudWatch dashboard config
│
├── design.md                  # Detailed architecture documentation
├── requirements.md            # System requirements specification
└── README.md                  # This file
```

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- Python 3.11+
- AWS CLI configured with appropriate credentials
- AWS account with permissions for Lambda, API Gateway, S3, DynamoDB, Textract
- EC2 instance running Ollama (or modify to use different LLM endpoint)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd <project-directory>
   ```

2. **Install frontend dependencies**
   ```bash
   cd PrototypeDemo/frontend
   npm install
   ```

3. **Install backend dependencies**
   ```bash
   cd ../backend
   pip install -r requirements.txt
   ```

### Deployment

#### Full AWS Deployment

The deployment script automates the entire infrastructure setup:

```bash
cd PrototypeDemo/infra
./deploy.sh
```

This script will:
1. Create S3 buckets for documents and frontend hosting
2. Create DynamoDB tables (Results, Users, AuditLog)
3. Set up IAM roles and policies
4. Package and deploy 5 Lambda functions
5. Configure API Gateway with CORS
6. Build and deploy the React frontend

**Deployment outputs:**
- API Gateway URL
- Frontend URL (S3 static website)
- Configuration saved to `deployment-config.txt`

#### Frontend-Only Deployment

To update just the frontend:

```bash
cd PrototypeDemo/infra
./deploy-frontend.sh
```

### Local Development

1. **Start the frontend development server**
   ```bash
   cd PrototypeDemo/frontend
   npm run dev
   ```

2. **Configure environment variables**
   
   Create `.env` file in `frontend/` directory:
   ```
   VITE_API_BASE_URL=https://your-api-gateway-url.amazonaws.com/prod
   ```

3. **Access the application**
   
   Open http://localhost:5173 in your browser

## API Endpoints

### POST /process
Upload and process a document
- **Input**: Multipart form data with file
- **Output**: `{ doc_id, status: "PROCESSING" }`
- **Timeout**: 30s (returns immediately, processing continues async)

### GET /status?doc_id={id}
Poll for processing status
- **Output**: `{ status, professional_summary, patient_explanation, ... }`
- **Status values**: `PROCESSING`, `PENDING`, `APPROVED`, `REJECTED`

### POST /approve
Approve or reject AI-generated content
- **Input**: `{ doc_id, action: "approve"|"reject", notes }`
- **Output**: `{ status, message }`

### GET /audit?doc_id={id}
Retrieve audit log for a document
- **Output**: `{ events: [...] }`

## Lambda Functions

### MediAssist-Process (30s timeout)
- Receives document upload
- Extracts text (PDF/DOCX/Image/Text)
- Stores in S3 and DynamoDB
- Triggers Worker async
- Returns doc_id immediately

### MediAssist-Worker (600s timeout)
- Calls Ollama LLM for AI processing
- Generates professional summary
- Creates patient-friendly explanation
- Updates DynamoDB with results
- No API Gateway timeout issues

### MediAssist-Status (30s timeout)
- Polled by frontend every 3 seconds
- Returns current processing status
- Provides AI-generated content when ready

### MediAssist-Approve (30s timeout)
- Handles human review workflow
- Updates document status
- Logs approval/rejection in audit trail

### MediAssist-Audit (30s timeout)
- Retrieves complete audit log
- Supports compliance tracking
- Returns chronological event history

## Configuration

### AWS Resources

**S3 Buckets:**
- `mediassistai-documents` - Document storage
- `mediassistai-frontend` - Static website hosting

**DynamoDB Tables:**
- `MediAssist-Results` - Processing results and status
- `MediAssist-Users` - User management
- `MediAssist-AuditLog` - Compliance audit trail

**Lambda Functions:**
- All functions use Python 3.11 runtime
- Memory: 256-512 MB
- Timeout: 30-600 seconds (depending on function)

### Environment Variables

Lambda functions use these environment variables:
- `OLLAMA_ENDPOINT` - Ollama API endpoint
- `OLLAMA_MODEL` - LLM model name (default: llama3.2:3b)
- `RESULTS_TABLE` - DynamoDB results table name
- `AUDIT_TABLE` - DynamoDB audit table name
- `DOCS_BUCKET` - S3 bucket for documents
- `WORKER_FUNCTION` - Worker Lambda function name

## Cleanup

To remove all AWS resources:

```bash
cd PrototypeDemo/infra
./cleanup.sh
```

This will delete:
- Lambda functions
- API Gateway
- DynamoDB tables
- S3 buckets (including all objects)
- IAM roles and policies

## Limitations

### Technical Limitations
- Maximum document size: 32,000 tokens
- Concurrent users: Up to 1,000 per deployment
- Processing time: 30-60 seconds for complex documents
- Language support: Initially English only

### Clinical Limitations
- **No diagnosis**: System cannot provide diagnostic opinions
- **No treatment advice**: No therapeutic recommendations
- **Synthetic data only**: Cannot process real patient information
- **Professional judgment required**: Cannot replace healthcare expertise

### Regulatory Scope
- Designed for US healthcare regulations
- Requires organizational AI adoption policies
- Staff training on capabilities and limitations required

## Security & Compliance

- TLS 1.3 encryption for all data in transit
- Data encrypted at rest in S3 and DynamoDB
- Role-based access controls (IAM)
- Comprehensive audit logging
- HIPAA-aligned practices
- No real patient data processing

## Responsible AI

This system implements responsible AI principles:

- **Transparency**: Clear explanations for AI outputs with confidence scores
- **Human oversight**: Healthcare professionals maintain final authority
- **Safety constraints**: Prevents diagnostic/treatment recommendations
- **Bias mitigation**: Regular evaluation for discriminatory outputs
- **Continuous improvement**: Professional feedback improves system performance

## Contributing

This is a prototype demonstration project. For production use, additional considerations are required:

- Enhanced security measures
- Comprehensive testing and validation
- Regulatory compliance verification
- Clinical validation with healthcare professionals
- Privacy impact assessments

## License

[Specify your license here]

## Contact

[Specify contact information here]

---

**Version**: 1.0  
**Last Updated**: March 2026  
**Status**: Prototype Demonstration

**Disclaimer**: This system is for demonstration purposes only and uses synthetic data. It does not provide medical advice, diagnosis, or treatment recommendations. Always consult qualified healthcare professionals for medical decisions.
