import { useState, useRef } from 'react'
import { useApp } from '../context/AppContext'

const UploadPanel = () => {
  const { file, setFile, setCurrentStep, setExtractedText, setAiResult, addAudit, formatSize, getDemoResult, API_BASE_URL } = useApp()
  const [dragOver, setDragOver] = useState(false)
  const [consent, setConsent] = useState(false)
  const [error, setError] = useState('')
  const fileInputRef = useRef()

  function handleFile(f) {
    if (!f) return
    const validTypes = ['application/pdf', 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
    if (!validTypes.includes(f.type) && !f.name.match(/\.(pdf|txt|docx)$/i)) {
      setError('Only PDF, TXT, and DOCX files are allowed.')
      return
    }
    if (f.size > 10 * 1024 * 1024) {
      setError('File size must be under 10MB.')
      return
    }
    setError('')
    setFile(f)
  }

  function removeFile() {
    setFile(null)
    fileInputRef.current.value = ''
  }

  async function startProcessing() {
    if (!file) return
    setCurrentStep(2)
    addAudit('UPLOAD', `File uploaded: ${file.name} (${formatSize(file.size)})`)

    let text = ''
    if (file.type === 'text/plain') {
      text = await file.text()
    } else {
      text = `Document: ${file.name}\n[Binary content — processed server-side]`
    }
    setExtractedText(text)

    setTimeout(async () => {
      try {
        const response = await fetch(`${API_BASE_URL}/process`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: text.substring(0, 8000), filename: file.name })
        })
        if (!response.ok) throw new Error('API error')
        const result = await response.json()
        setAiResult(result)
        addAudit('GENERATE', `AI summary generated. Confidence: ${result.confidence_score}/100`)
      } catch {
        const demo = getDemoResult()
        setAiResult(demo)
        addAudit('GENERATE', `AI summary generated. Confidence: ${demo.confidence_score}/100`)
      }
      setTimeout(() => setCurrentStep(3), 500)
    }, 6000)
  }

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Upload Clinical Document</div>
        <div className="card-subtitle">
          Upload a synthetic or publicly available clinical/research document. Patient data must NOT be used in this prototype.
        </div>

        <div
          className={`upload-zone ${dragOver ? 'drag-over' : ''}`}
          onDragOver={e => { e.preventDefault(); setDragOver(true) }}
          onDragLeave={() => setDragOver(false)}
          onDrop={e => { e.preventDefault(); setDragOver(false); handleFile(e.dataTransfer.files[0]) }}
          onClick={() => fileInputRef.current.click()}
        >
          <input
            ref={fileInputRef}
            type="file"
            accept=".pdf,.txt,.docx"
            style={{ display: 'none' }}
            onChange={e => handleFile(e.target.files[0])}
          />
          <span className="upload-icon">📄</span>
          <div className="upload-title">Drop your document here</div>
          <div className="upload-sub">or click to browse files</div>
          <div className="upload-limits">
            <span className="upload-limit-tag">PDF</span>
            <span className="upload-limit-tag">TXT</span>
            <span className="upload-limit-tag">DOCX</span>
            <span className="upload-limit-tag">Max 10MB</span>
          </div>
        </div>

        {error && (
          <div className="error-box visible" style={{ marginTop: 12 }}>
            ❌ <span>{error}</span>
          </div>
        )}

        {file && (
          <div className="file-preview visible">
            <div className="file-icon-box">📄</div>
            <div>
              <div className="file-name">{file.name}</div>
              <div className="file-size">{formatSize(file.size)}</div>
            </div>
            <button className="file-remove" onClick={e => { e.stopPropagation(); removeFile() }}>✕</button>
          </div>
        )}

        <div className="disclaimer" style={{ marginTop: 20 }}>
          <span className="disclaimer-icon">⚠️</span>
          <p><strong>Important:</strong> Do not upload real patient data. This prototype uses synthetic data only. All outputs require professional review before any clinical use.</p>
        </div>

        <div className="checkbox-row">
          <input
            type="checkbox"
            id="consentCheck"
            checked={consent}
            onChange={e => setConsent(e.target.checked)}
          />
          <label htmlFor="consentCheck">
            I confirm this document does not contain real patient data and I understand this tool is for demonstration purposes only.
          </label>
        </div>

        <div className="btn-row">
          <button
            className="btn btn-primary"
            disabled={!file || !consent}
            onClick={startProcessing}
          >
            🚀 Process Document
          </button>
        </div>
      </div>
    </div>
  )
}

export default UploadPanel
