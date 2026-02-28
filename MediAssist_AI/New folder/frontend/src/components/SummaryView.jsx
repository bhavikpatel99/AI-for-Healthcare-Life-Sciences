export function SummaryView({ result }) {
  if (!result) {
    return (
      <section className="panel placeholder">
        <h2>2. AI Clinical Summary & Key Points</h2>
        <p>Run an analysis to see a concise professional summary, key findings, and confidence indicators.</p>
      </section>
    )
  }

  const { summary, keyFindings, confidence, safetyFlags } = result

  return (
    <section className="panel">
      <h2>2. AI Clinical Summary & Key Points</h2>

      <div className="summary-block">
        <h3>Professional summary</h3>
        <p className="summary-text">{summary}</p>
      </div>

      {Array.isArray(keyFindings) && keyFindings.length > 0 && (
        <div className="summary-block">
          <h3>Key findings</h3>
          <ul className="bullet-list">
            {keyFindings.map((item, index) => (
              <li key={index}>{item}</li>
            ))}
          </ul>
        </div>
      )}

      {confidence && (
        <div className="summary-block">
          <h3>Confidence indicators</h3>
          <div className="confidence-grid">
            {Object.entries(confidence).map(([label, value]) => (
              <div key={label} className="confidence-item">
                <div className="confidence-label">
                  <span>{label}</span>
                  <span>{Math.round(value * 100)}%</span>
                </div>
                <div className="confidence-bar">
                  <div className="confidence-bar-fill" style={{ width: `${Math.round(value * 100)}%` }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {Array.isArray(safetyFlags) && safetyFlags.length > 0 && (
        <div className="summary-block warnings">
          <h3>Safety & compliance checks</h3>
          <ul className="bullet-list">
            {safetyFlags.map((flag, index) => (
              <li key={index}>{flag}</li>
            ))}
          </ul>
        </div>
      )}
    </section>
  )
}

