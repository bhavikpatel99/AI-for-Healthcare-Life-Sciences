import { createContext, useContext, useState } from 'react'

const AppContext = createContext()

export function AppProvider({ children }) {
  const [currentStep, setCurrentStep] = useState(1)
  const [file, setFile] = useState(null)
  const [extractedText, setExtractedText] = useState('')
  const [aiResult, setAiResult] = useState(null)
  const [approved, setApproved] = useState(false)
  const [auditLog, setAuditLog] = useState([])

  const API_BASE_URL = 'https://wt7l9acl3l.execute-api.us-east-1.amazonaws.com/prod'

  function addAudit(type, detail) {
    const entry = {
      type, detail,
      time: new Date().toLocaleTimeString(),
      timestamp: new Date().toISOString()
    }
    setAuditLog(prev => [...prev, entry])
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  }

  function getDemoResult() {
    return {
      professional_summary: "This document presents a clinical overview of patient management protocols for Type 2 Diabetes Mellitus. Key findings include: elevated HbA1c levels (8.2%) indicating suboptimal glycemic control, recommendation for metformin dose adjustment (500mg → 1000mg twice daily), and referral for dietary counseling. Comorbidities noted: hypertension (BP 145/92mmHg), managed with lisinopril 10mg. Follow-up scheduled in 8 weeks.",
      patient_explanation: "Your doctor's notes show that your blood sugar levels have been higher than the target range, so your diabetes medicine dose will be increased. Your blood pressure is also slightly high. Your doctor wants you to meet with a nutritionist. A follow-up visit is planned in 8 weeks.",
      confidence_score: 82,
      disclaimer: "This AI-generated summary is intended to assist healthcare professionals only. It is not a diagnostic tool and should not replace clinical judgment. All outputs must be reviewed by a qualified healthcare professional before any patient use."
    }
  }

  function resetAll() {
    setFile(null)
    setExtractedText('')
    setAiResult(null)
    setApproved(false)
    setAuditLog([])
    setCurrentStep(1)
  }

  return (
    <AppContext.Provider value={{
      currentStep, setCurrentStep,
      file, setFile,
      extractedText, setExtractedText,
      aiResult, setAiResult,
      approved, setApproved,
      auditLog, addAudit,
      API_BASE_URL, formatSize, getDemoResult, resetAll
    }}>
      {children}
    </AppContext.Provider>
  )
}

export function useApp() {
  return useContext(AppContext)
}