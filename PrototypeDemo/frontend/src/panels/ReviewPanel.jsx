import { useState, useEffect } from "react";
import { useApp } from "../context/AppContext";

const ReviewPanel = () => {
  const {
    aiResult,
    setApproved,
    setCurrentStep,
    addAudit,
    resetAll,
    API_BASE_URL,
  } = useApp();
  const [profText, setProfText] = useState("");
  const [patText, setPatText] = useState("");
  const [isApproved, setIsApproved] = useState(false);

  // if (aiResult && !profText && !patText) {
  //   setProfText(aiResult.professional_summary);
  //   setPatText(aiResult.patient_explanation);
  // }
  useEffect(() => {
    if (aiResult) {
      setProfText(aiResult.professional_summary || "");
      setPatText(aiResult.patient_explanation || "");
    }
  }, [aiResult]);

  if (!aiResult) return null;

  const score = aiResult.confidence_score;
  const color =
    score >= 75
      ? "var(--green)"
      : score >= 50
        ? "var(--warn)"
        : "var(--danger)";
  const dotClass =
    score >= 75 ? "conf-high" : score >= 50 ? "conf-med" : "conf-low";

  async function approve() {
    try {
      const response = await fetch(`${API_BASE_URL}/approve`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          doc_id: aiResult.doc_id,
        }),
      });

      if (!response.ok) throw new Error("Approval failed");

      setIsApproved(true);
      setApproved(true);

      addAudit(
        "APPROVE",
        "Document approved by healthcare professional. Patient explanation released.",
      );

      setTimeout(() => setCurrentStep(4), 800);
    } catch (err) {
      console.error("Approval failed:", err);
      alert("Approval failed. Please try again.");
    }
  }

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Review & Approve</div>
        <div className="card-subtitle">
          Carefully review the AI-generated outputs below. You may edit before
          approving.
        </div>

        <div
          className={`status-banner ${isApproved ? "status-approved" : "status-pending"}`}
        >
          {isApproved
            ? "✅ Approved — Patient explanation released."
            : "⏳ Pending Review — Carefully review and edit the AI outputs. Click Approve when satisfied."}
        </div>

        <div className="full-width-section" style={{ marginBottom: 20 }}>
          <div className="result-section-title" style={{ marginBottom: 8 }}>
            Confidence Score
          </div>
          <div className="confidence-ring">
            <span className={`conf-dot ${dotClass}`}></span> {score} / 100
          </div>
          <div className="confidence-bar-wrap">
            <div className="confidence-bar">
              <div
                className="confidence-bar-fill"
                style={{ width: `${score}%`, background: color }}
              ></div>
            </div>
          </div>
        </div>

        <div className="result-grid">
          <div className="result-section">
            <div className="result-section-header">
              <span className="result-section-title">Professional Summary</span>
            </div>
            <textarea
              style={{
                width: "100%",
                background: "transparent",
                border: "1px solid var(--border)",
                borderRadius: 8,
                color: "var(--text)",
                fontFamily: "inherit",
                fontSize: 14,
                lineHeight: 1.7,
                padding: 12,
                resize: "vertical",
              }}
              value={profText}
              onChange={(e) => {
                setProfText(e.target.value);
                addAudit("EDIT", "Professional Summary edited by reviewer");
              }}
              rows={8}
            />
          </div>
          <div className="result-section">
            <div className="result-section-header">
              <span className="result-section-title">
                Patient-Friendly Explanation
              </span>
            </div>
            <textarea
              style={{
                width: "100%",
                background: "transparent",
                border: "1px solid var(--border)",
                borderRadius: 8,
                color: "var(--text)",
                fontFamily: "inherit",
                fontSize: 14,
                lineHeight: 1.7,
                padding: 12,
                resize: "vertical",
              }}
              value={patText}
              onChange={(e) => {
                setPatText(e.target.value);
                addAudit("EDIT", "Patient Explanation edited by reviewer");
              }}
              rows={8}
            />
            <div
              style={{ marginTop: 10, fontSize: 11, color: "var(--text-dim)" }}
            >
              ⚠ Not released to patient until approved
            </div>
          </div>
        </div>

        <div
          className="full-width-section"
          style={{ marginBottom: 20, marginTop: 20 }}
        >
          <div className="result-section-title" style={{ marginBottom: 8 }}>
            AI Safety Disclaimer
          </div>
          <div className="result-text">{aiResult.disclaimer}</div>
        </div>

        <div className="info-box" style={{ marginBottom: 20 }}>
          ℹ️ Editing is tracked in the audit log. Once you approve, the patient
          explanation becomes available for sharing.
        </div>

        <div className="btn-row">
          <button
            className="btn btn-approve"
            disabled={isApproved}
            onClick={approve}
          >
            ✅ Approve &amp; Release Patient Explanation
          </button>
          <button className="btn btn-danger" onClick={resetAll}>
            ↩ Start Over
          </button>
        </div>
      </div>
    </div>
  );
};

export default ReviewPanel;
