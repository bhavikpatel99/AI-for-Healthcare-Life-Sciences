import { useEffect, useState } from 'react'

const STORAGE_KEY = 'ai-healthcare-history'

export function HistoryView() {
  const [items, setItems] = useState([])

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(STORAGE_KEY)
      if (stored) {
        setItems(JSON.parse(stored))
      }
    } catch {
      // ignore
    }
  }, [])

  if (!items.length) {
    return (
      <section className="panel placeholder">
        <h2>Recent Analyses</h2>
        <p>When you run analyses, a local-only history will appear here for convenience (not stored on the server).</p>
      </section>
    )
  }

  return (
    <section className="panel">
      <h2>Recent Analyses</h2>
      <p className="helper">History is stored only in your browser (localStorage) for this prototype.</p>

      <ul className="history-list">
        {items.map((item) => (
          <li key={item.id} className="history-item">
            <div className="history-header">
              <span className="history-title">{item.title}</span>
              <span className="history-meta">{new Date(item.createdAt).toLocaleString()}</span>
            </div>
            <p className="history-summary">{item.summary}</p>
          </li>
        ))}
      </ul>
    </section>
  )
}

