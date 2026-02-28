import axios from 'axios'

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:4000'

function persistToHistory(result) {
  try {
    const STORAGE_KEY = 'ai-healthcare-history'
    const existing = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || '[]')
    const entry = {
      id: result.id,
      title: result.title || 'Synthetic clinical document',
      summary: result.summary,
      createdAt: result.createdAt
    }
    const updated = [entry, ...existing].slice(0, 20)
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(updated))
  } catch {
    // non-critical
  }
}

export async function analyzeDocument({ text, file, audience }) {
  let payload = { audience }

  if (text) {
    payload.text = text
    payload.sourceType = 'text'
  } else if (file) {
    const content = await file.text()
    payload.text = content
    payload.sourceType = 'file'
    payload.filename = file.name
  }

  const response = await axios.post(`${API_BASE_URL}/api/analyze`, payload, {
    headers: {
      'Content-Type': 'application/json'
    }
  })

  const result = response.data
  persistToHistory(result)
  return result
}

