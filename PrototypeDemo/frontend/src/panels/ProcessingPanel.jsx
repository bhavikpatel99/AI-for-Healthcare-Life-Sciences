import { useEffect, useState } from 'react'
import { useApp } from '../context/AppContext'

const loadingSteps = [
  'Uploading to secure storage…',
  'Extracting text content…',
  'Analyzing clinical terminology…',
  'Generating professional summary…',
  'Creating patient-friendly explanation…',
  'Calculating confidence score…'
]

const ProcessingPanel = () => {
  const { currentStep } = useApp()
  const [activeStep, setActiveStep] = useState(0)

  useEffect(() => {
    if (currentStep !== 2) return
    setActiveStep(0)
    const delays = [0, 600, 1200, 1900, 2700, 4500]
    delays.forEach((delay, i) => {
      setTimeout(() => setActiveStep(i), delay)
    })
  }, [currentStep])

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">AI Processing</div>
        <div className="card-subtitle">Please wait while MediAssist AI analyzes your document…</div>
        <div className="loading-overlay active">
          <div className="spinner"></div>
          <div className="loading-text">Analyzing document…</div>
          <div className="loading-steps">
            {loadingSteps.map((label, i) => (
              <div
                key={i}
                className={`loading-step ${i === activeStep ? 'active' : ''} ${i < activeStep ? 'done' : ''}`}
              >
                <span className="loading-step-dot"></span>
                {label}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

export default ProcessingPanel
