import { createContext, useContext, useState } from 'react'

const AppContext = createContext()

export function AppProvider({ children }) {

  const [currentStep, setCurrentStep] = useState(1)
  const [file, setFile] = useState(null)
  const [extractedText, setExtractedText] = useState('')
  const [aiResult, setAiResult] = useState(null)
  const [approved, setApproved] = useState(false)
  const [auditLog, setAuditLog] = useState([])

  // ✅ Correct Vite ENV
  const API_BASE_URL = import.meta.env.VITE_API_BASE_URL
  console.log("API Base URL:", API_BASE_URL)

  function addAudit(type, detail) {
    const entry = {
      type,
      detail,
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
      professional_summary: "Demo summary...",
      patient_explanation: "Demo explanation...",
      confidence_score: 82,
      disclaimer: "AI demo output"
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
      API_BASE_URL,
      formatSize,
      getDemoResult,
      resetAll
    }}>
      {children}
    </AppContext.Provider>
  )
}

export function useApp() {
  return useContext(AppContext)
}