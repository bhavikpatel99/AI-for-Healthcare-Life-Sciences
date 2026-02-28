const { v4: uuidv4 } = require('uuid')
const { invokeModel } = require('./bedrockClient')

function buildPrompt({ text, audience }) {
  return `
You are an AI assistant helping healthcare professionals review synthetic or publicly available clinical or research documents.

The input below is NOT real patient data. It is synthetic or public text used for prototyping.

Your goals:
- Generate a concise, professional clinical-style summary.
- List 3–8 key findings or observations.
- Provide a patient-friendly explanation (plain language, no diagnosis or treatment advice).
- Provide confidence scores between 0 and 1 for overall summary, key findings, and patient explanation.
- Highlight any safety or compliance concerns, especially if the text appears to contain real patient data or requests diagnosis/treatment.

CRITICAL SAFETY RULES:
- Do NOT provide diagnoses.
- Do NOT recommend specific treatments, medications, or dosages.
- If the text seems to describe a real patient, clearly note this as a safety flag.

Return ONLY a strict JSON object with this shape:
{
  "summary": "string",
  "keyFindings": ["string", "..."],
  "patientExplanation": "string",
  "confidence": {
    "summary": 0.0,
    "keyFindings": 0.0,
    "patientExplanation": 0.0
  },
  "safetyFlags": ["string", "..."]
}

Text to analyze:
"""${text}"""

Audience preference: ${audience}.
`
}

async function analyzeDocument({ text, audience }) {
  const trimmed = (text || '').trim()
  if (!trimmed) {
    throw new Error('Document text is required')
  }

  const audienceValue = audience || 'professional'
  const now = new Date()

  const prompt = buildPrompt({ text: trimmed, audience: audienceValue })
  const raw = await invokeModel(prompt)

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    parsed = {
      summary: trimmed.slice(0, 400),
      keyFindings: ['Model returned unexpected format; using fallback summary.'],
      patientExplanation: 'This is a fallback explanation. Please re-run the analysis.',
      confidence: {
        summary: 0.4,
        keyFindings: 0.3,
        patientExplanation: 0.3
      },
      safetyFlags: ['Model output could not be parsed exactly as JSON.']
    }
  }

  return {
    id: uuidv4(),
    title: 'Synthetic clinical document',
    summary: parsed.summary,
    keyFindings: parsed.keyFindings || [],
    patientExplanation: parsed.patientExplanation,
    confidence: parsed.confidence || {
      summary: 0.5,
      keyFindings: 0.5,
      patientExplanation: 0.5
    },
    safetyFlags: parsed.safetyFlags || [],
    createdAt: now.toISOString(),
    audience: audienceValue,
    meta: {
      syntheticOnly: true
    }
  }
}

module.exports = {
  analyzeDocument
}

