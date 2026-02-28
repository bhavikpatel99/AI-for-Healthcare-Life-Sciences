import { useState } from 'react'
import { AnalyzeForm } from './components/AnalyzeForm.jsx'
import { SummaryView } from './components/SummaryView.jsx'
import { PatientView } from './components/PatientView.jsx'
import { HistoryView } from './components/HistoryView.jsx'

const TABS = ['Analyze', 'Patient View', 'History']

function App() {
  const [activeTab, setActiveTab] = useState('Analyze')
  const [analysisResult, setAnalysisResult] = useState(null)

  return (
    <div className="app-root">
      <header className="app-header">
        <div>
          <h1>AI Healthcare Workflow Support</h1>
          <p className="subtitle">
            Synthetic clinical document summarization with patient-friendly explanations and human review.
          </p>
        </div>
        <span className="badge">Prototype · Synthetic Data Only</span>
      </header>

      <nav className="tabs">
        {TABS.map((tab) => (
          <button
            key={tab}
            type="button"
            className={tab === activeTab ? 'tab active' : 'tab'}
            onClick={() => setActiveTab(tab)}
          >
            {tab}
          </button>
        ))}
      </nav>

      <main className="app-main">
        {activeTab === 'Analyze' && (
          <div className="layout">
            <AnalyzeForm onAnalysisComplete={setAnalysisResult} />
            <SummaryView result={analysisResult} />
          </div>
        )}
        {activeTab === 'Patient View' && <PatientView result={analysisResult} />}
        {activeTab === 'History' && <HistoryView />}
      </main>

      <footer className="app-footer">
        <p>
          This prototype works on synthetic or public clinical content only and does not provide diagnosis or treatment
          recommendations.
        </p>
      </footer>
    </div>
  )
}

export default App

