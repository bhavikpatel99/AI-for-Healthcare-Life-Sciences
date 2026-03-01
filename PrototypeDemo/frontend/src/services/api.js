const BASE_URL = process.env.production.REACT_APP_BASE_URL
console.log("API Base URL:", BASE_URL)
// Upload + Process Document
export const processDocument = async (file) => {
  const formData = new FormData()
  formData.append("file", file)

  const response = await fetch(`${BASE_URL}/process`, {
    method: "POST",
    body: formData
  })

  return response.json()
}

// Approve Document
export const approveDocument = async (doc_id) => {
  const response = await fetch(`${BASE_URL}/approve`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ doc_id })
  })

  return response.json()
}

// Get Audit Logs
export const getAuditLogs = async () => {
  const response = await fetch(`${BASE_URL}/audit`)
  return response.json()
}