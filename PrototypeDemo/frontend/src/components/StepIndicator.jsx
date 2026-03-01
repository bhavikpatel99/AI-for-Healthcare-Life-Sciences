import { useApp } from '../context/AppContext'

const steps = ['Upload Document', 'AI Processing', 'Review & Approve', 'Export & Audit']

const StepIndicator = () => {
  const { currentStep } = useApp()

  return (
    <div className="steps">
      {steps.map((label, i) => {
        const num = i + 1
        const isDone = num < currentStep
        const isActive = num === currentStep
        return (
          <div
            key={num}
            className={`step ${isActive ? 'active' : ''} ${isDone ? 'done' : ''}`}
          >
            <span className="step-num">{isDone ? '✓' : num}</span>
            {label}
          </div>
        )
      })}
    </div>
  )
}

export default StepIndicator
