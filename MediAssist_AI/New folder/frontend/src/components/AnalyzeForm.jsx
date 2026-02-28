import { useState } from 'react'
import { analyzeDocument } from '../services/apiClient.js'

export function AnalyzeForm({ onAnalysisComplete }) {
  const [inputMode, setInputMode] = useState('text')
  const [text, setText] = useState('')
  const [file, setFile] = useState(null)
  const [audience, setAudience] = useState('professional')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  async function handleSubmit(event) {
    event.preventDefault()
    setError(null)

    if (inputMode === 'text' && !text.trim()) {
      setError('Please paste a synthetic clinical or research note.')
      return
    }

    if (inputMode === 'file' && !file) {
      setError('Please select a PDF or text file.')
      return
    }

    setLoading(true)
    try {
      const result = await analyzeDocument({
        text: inputMode === 'text' ? text : null,
        file,
        audience
      })
      onAnalysisComplete?.(result)
    } catch (err) {
      setError(err.message || 'Analysis failed. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <section className="panel">
      <h2>1. Upload or Paste Synthetic Document</h2>
      <p className="helper">
        Use only synthetic or publicly available clinical / research documents. No real patient data should be used.
      </p>

      <div className="field-group">
        <label className="label">Input mode</label>
        <div className="segmented-control">
          <button
            type="button"
            className={inputMode === 'text' ? 'segment active' : 'segment'}
            onClick={() => {
              setInputMode('text')
              setFile(null)
            }}
          >
            Paste text
          </button>
          <button
            type="button"
            className={inputMode === 'file' ? 'segment active' : 'segment'}
            onClick={() => {
              setInputMode('file')
              setText('')
            }}
          >
            Upload file (PDF / TXT)
          </button>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="form">
        {inputMode === 'text' ? (
          <div className="field">
            <label className="label" htmlFor="clinical-text">
              Synthetic clinical / research note
            </label>
            <textarea
              id="clinical-text"
              className="textarea"
              rows={10}
              placeholder="Paste synthetic clinical or research text here..."
              value={text}
              onChange={(e) => setText(e.target.value)}
            />
          </div>
        ) : (
          <div className="field">
            <label className="label" htmlFor="file-input">
              Upload synthetic document
            </label>
            <input
              id="file-input"
              type="file"
              accept=".pdf,.txt"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
            <p className="helper">Files are processed in-memory for this prototype; they are not persisted.</p>
          </div>
        )}

        <div className="field">
          <label className="label">Target audience for explanation</label>
          <select
            className="select"
            value={audience}
            onChange={(e) => setAudience(e.target.value)}
          >
            <option value="professional">Healthcare professional</option>
            <option value="patient">Patient-friendly</option>
            <option value="both">Both professional and patient views</option>
          </select>
        </div>

        {error && <p className="error">{error}</p>}

        <button className="primary-button" type="submit" disabled={loading}>
          {loading ? 'Analyzing…' : 'Analyze document'}
        </button>
      </form>
    </section>
  )
}

