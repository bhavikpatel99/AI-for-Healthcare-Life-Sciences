import { useState, useRef } from "react";
import { useApp } from "../context/AppContext";

const UploadPanel = () => {
  const {
    file,
    setFile,
    setCurrentStep,
    setExtractedText,
    setAiResult,
    addAudit,
    formatSize,
    getDemoResult,
    API_BASE_URL,
  } = useApp();

  const [dragOver,    setDragOver]    = useState(false);
  const [consent,     setConsent]     = useState(false);
  const [error,       setError]       = useState("");
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef();

  function handleFile(f) {
    if (!f) return;
    const validTypes = [
      "application/pdf",
      "text/plain",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "image/jpeg", "image/png", "image/tiff", "image/bmp", "image/webp",
    ];
    if (!validTypes.includes(f.type) && !f.name.match(/\.(pdf|txt|docx|jpg|jpeg|png|tiff|tif|bmp|webp)$/i)) {
      setError("Allowed formats: PDF, TXT, DOCX, JPG, PNG, TIFF, BMP, WEBP");
      return;
    }
    if (f.size > 10 * 1024 * 1024) {
      setError("File size must be under 10MB.");
      return;
    }
    setError("");
    setFile(f);
  }

  function removeFile() {
    setFile(null);
    fileInputRef.current.value = "";
  }

  async function startProcessing() {
    if (!file) return;

    setIsUploading(true);
    setError("");

    addAudit("UPLOAD", `File uploaded: ${file.name} (${formatSize(file.size)})`);

    // Extract text locally (for TXT files only — others processed server-side)
    let text = "";
    if (file.type === "text/plain") {
      text = await file.text();
    } else {
      text = `Document: ${file.name}\n[Binary content — processed server-side]`;
    }
    setExtractedText(text);

    try {
      const formData = new FormData();
      formData.append("file", file);

      const response = await fetch(`${API_BASE_URL}/process`, {
        method: "POST",
        body: formData,
      });

      if (!response.ok) throw new Error(`API error (${response.status})`);

      const result = await response.json();

      // ✅ Fix 1: Removed setTimeout(6000) — no artificial wait needed
      // process now returns instantly with {doc_id, status:"PROCESSING"}
      // ReviewPanel handles the polling from here
      setAiResult(result);
      addAudit("SUBMIT", `Document sent for AI processing. doc_id: ${result.doc_id}`);

      // ✅ Fix 2: Move to ReviewPanel immediately — it will show loading spinner
      setCurrentStep(3);

    } catch (err) {
      console.error("Upload failed:", err);

      // ✅ Fix 3: Demo fallback uses "High" not 82 — matches backend format
      const demo = getDemoResult();
      setAiResult(demo);
      addAudit("GENERATE", `Demo mode — AI summary generated. Confidence: ${demo.confidence_score}`);
      setCurrentStep(3);

    } finally {
      setIsUploading(false);
    }
  }

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Upload Clinical Document</div>
        <div className="card-subtitle">
          Upload a synthetic or publicly available clinical/research document.
          Patient data must NOT be used in this prototype.
        </div>

        <div
          className={`upload-zone ${dragOver ? "drag-over" : ""}`}
          onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            handleFile(e.dataTransfer.files[0]);
          }}
          onClick={() => fileInputRef.current.click()}
        >
          <input
            ref={fileInputRef}
            type="file"
            accept=".pdf,.txt,.docx,.jpg,.jpeg,.png,.tiff,.tif,.bmp,.webp"
            style={{ display: "none" }}
            onChange={(e) => handleFile(e.target.files[0])}
          />
          <span className="upload-icon">📄</span>
          <div className="upload-title">Drop your document here</div>
          <div className="upload-sub">or click to browse files</div>
          <div className="upload-limits">
            <span className="upload-limit-tag">PDF</span>
            <span className="upload-limit-tag">TXT</span>
            <span className="upload-limit-tag">DOCX</span>
            <span className="upload-limit-tag">JPG</span>
            <span className="upload-limit-tag">PNG</span>
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
            <button
              className="file-remove"
              onClick={(e) => { e.stopPropagation(); removeFile(); }}
            >
              ✕
            </button>
          </div>
        )}

        <div className="disclaimer" style={{ marginTop: 20 }}>
          <span className="disclaimer-icon">⚠️</span>
          <p>
            <strong>Important:</strong> Do not upload real patient data. This
            prototype uses synthetic data only. All outputs require professional
            review before any clinical use.
          </p>
        </div>

        <div className="checkbox-row">
          <input
            type="checkbox"
            id="consentCheck"
            checked={consent}
            onChange={(e) => setConsent(e.target.checked)}
          />
          <label htmlFor="consentCheck">
            I confirm this document does not contain real patient data and I
            understand this tool is for demonstration purposes only.
          </label>
        </div>

        <div className="btn-row">
          <button
            className="btn btn-primary"
            disabled={!file || !consent || isUploading}
            onClick={startProcessing}
          >
            {isUploading ? "⏳ Uploading..." : "🚀 Process Document"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default UploadPanel;