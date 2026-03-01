import { useApp } from '../context/AppContext'

const ExportPanel = () => {
  const { aiResult, auditLog, resetAll } = useApp()

  function exportSummary() {
    if (!aiResult) return
    const content = `MEDIASSIST AI — CLINICAL SUMMARY EXPORT
Generated: ${new Date().toISOString()}
Confidence Score: ${aiResult.confidence_score}/100

PROFESSIONAL SUMMARY:
${aiResult.professional_summary}

PATIENT EXPLANATION:
${aiResult.patient_explanation}

AUDIT LOG:
${auditLog.map(e => `[${e.time}] ${e.type}: ${e.detail}`).join('\n')}

---
AI-Assisted. Not a diagnostic tool. Requires professional validation.
MediAssist AI · Team Cyber Scorpion`

    const blob = new Blob([content], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = 'mediassist-summary.txt'; a.click()
    URL.revokeObjectURL(url)
  }

  function copyJSON() {
    const output = {
      metadata: { timestamp: new Date().toISOString(), confidence: aiResult?.confidence_score, status: 'APPROVED' },
      professional_summary: aiResult?.professional_summary,
      patient_explanation: aiResult?.patient_explanation,
      disclaimer: aiResult?.disclaimer,
      audit_log: auditLog
    }
    navigator.clipboard.writeText(JSON.stringify(output, null, 2))
    alert('JSON copied to clipboard!')
  }

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Export & Audit Trail</div>
        <div className="card-subtitle">The document has been approved. Export summaries and review the complete audit log.</div>

        <div className="patient-card" style={{ marginBottom: 20 }}>
          <div className="patient-card-title">
            🏥 Patient Explanation
            <span style={{ fontSize: 13, fontWeight: 400, color: 'var(--green)', marginLeft: 8 }}>✅ Approved for Sharing</span>
          </div>
          <div className="patient-text">{aiResult?.patient_explanation}</div>
        </div>

        <div className="full-width-section" style={{ marginBottom: 20 }}>
          <div className="result-section-title" style={{ marginBottom: 16 }}>Export Options</div>
          <div className="export-actions">
            <button className="btn btn-primary" onClick={exportSummary}>⬇ Download Summary</button>
            <button className="btn btn-secondary" onClick={copyJSON}>📋 Copy JSON Output</button>
            <button className="btn btn-secondary" onClick={() => window.print()}>🖨 Print Audit Log</button>
          </div>
        </div>

        <div className="full-width-section">
          <div className="result-section-title" style={{ marginBottom: 16 }}>Full Audit Trail</div>
          <div className="audit-log">
            {auditLog.map((entry, i) => (
              <div key={i} className="audit-entry">
                <span className={`audit-type audit-${entry.type}`}>{entry.type}</span>
                <span className="audit-detail">{entry.detail}</span>
                <span className="audit-time">{entry.time}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="btn-row" style={{ marginTop: 20 }}>
          <button className="btn btn-secondary" onClick={resetAll}>🔄 Process Another Document</button>
        </div>
      </div>
    </div>
  )
}

export default ExportPanel
