import { useState, useEffect, useRef } from "react";
import { useApp } from "../context/AppContext";

const ReviewPanel = () => {
  const {
    aiResult,
    setAiResult,
    setApproved,
    setCurrentStep,
    addAudit,
    resetAll,
    API_BASE_URL,
  } = useApp();

  const [profText, setProfText] = useState("");
  const [patText, setPatText] = useState("");
  const [isApproved, setIsApproved] = useState(false);
  const [polling, setPolling] = useState(false);
  const [pollMsg, setPollMsg] = useState("Processing document...");
  const [pollError, setPollError] = useState("");
  const pollRef = useRef(null);

  // ── Start polling when process returns {status:"PROCESSING"} ──────────────
  useEffect(() => {
    if (aiResult?.status === "PROCESSING" && !polling) {
      startPolling(aiResult.doc_id);
    }
  }, [aiResult]);

  // ── Fill text areas once real result arrives ───────────────────────────────
  useEffect(() => {
    if (aiResult && aiResult.status !== "PROCESSING") {
      setProfText(aiResult.professional_summary || "");
      setPatText(aiResult.patient_explanation || "");
    }
  }, [aiResult]);

  // ── Cleanup interval on unmount ────────────────────────────────────────────
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  // ── Poll GET /status every 5 seconds until done ───────────────────────────
  function startPolling(doc_id) {
    setPolling(true);
    setPollMsg("AI is analysing your document...");
    let attempts = 0;
    const MAX = 60; // 60 × 5s = 5 min max

    pollRef.current = setInterval(async () => {
      attempts++;
      setPollMsg(`Processing... (${attempts * 5}s elapsed)`);

      try {
        // const res  = await fetch(`${API_BASE_URL}/status?doc_id=${doc_id}`);
        // const data = await res.json();

        // if (data.status === "PROCESSING") return; // still running

        const res = await fetch(`${API_BASE_URL}/status?doc_id=${doc_id}`);
        const raw = await res.json();

        // API Gateway wraps result in a "body" string — unwrap it
        const data = typeof raw.body === "string" ? JSON.parse(raw.body) : raw;

        if (data.status === "PROCESSING") return;
        clearInterval(pollRef.current);
        setPolling(false);

        if (data.status === "FAILED") {
          setPollError(`Processing failed: ${data.error || "Unknown error"}`);
          return;
        }

        // ✅ Got result — merge into context
        setAiResult({ ...data, doc_id });
      } catch (err) {
        setPollMsg(`Retrying... (${err.message})`);
      }

      if (attempts >= MAX) {
        clearInterval(pollRef.current);
        setPolling(false);
        setPollError("Timed out. Please try again.");
      }
    }, 5000);
  }

  if (!aiResult) return null;

  // ── Loading screen while Ollama works ─────────────────────────────────────
  if (polling || aiResult?.status === "PROCESSING") {
    return (
      <div className="panel active">
        <div className="card" style={{ textAlign: "center", padding: 60 }}>
          <div style={{ fontSize: 48, marginBottom: 20 }}>🧠</div>
          <div className="card-title">AI is Processing Your Document</div>
          <div
            className="card-subtitle"
            style={{ marginTop: 12, marginBottom: 24 }}
          >
            {pollMsg}
          </div>
          <div
            style={{
              width: "100%",
              height: 6,
              background: "var(--border)",
              borderRadius: 3,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                height: "100%",
                width: "40%",
                background: "var(--primary)",
                borderRadius: 3,
                animation: "pulse 1.5s ease-in-out infinite",
              }}
            />
          </div>
          <div
            style={{ marginTop: 16, fontSize: 12, color: "var(--text-dim)" }}
          >
            This may take 30–90 seconds depending on document length
          </div>
          {pollError && (
            <div
              style={{
                marginTop: 20,
                padding: 12,
                borderRadius: 8,
                background: "#fee2e2",
                color: "#dc2626",
              }}
            >
              ❌ {pollError}
              <br />
              <button
                className="btn btn-danger"
                style={{ marginTop: 12 }}
                onClick={resetAll}
              >
                Start Over
              </button>
            </div>
          )}
        </div>
      </div>
    );
  }

  // ── Error screen ──────────────────────────────────────────────────────────
  if (pollError) {
    return (
      <div className="panel active">
        <div className="card" style={{ textAlign: "center", padding: 40 }}>
          <div style={{ fontSize: 48, marginBottom: 16 }}>❌</div>
          <div className="card-title">Processing Failed</div>
          <div className="card-subtitle" style={{ marginTop: 8 }}>
            {pollError}
          </div>
          <button
            className="btn btn-danger"
            style={{ marginTop: 24 }}
            onClick={resetAll}
          >
            Start Over
          </button>
        </div>
      </div>
    );
  }

  // ── Confidence score: handles "High"/"Medium"/"Low" OR numeric ────────────
  const rawScore = aiResult.confidence_score;
  const scoreMap = { high: 85, medium: 60, low: 30 };
  const score =
    typeof rawScore === "number"
      ? rawScore
      : (scoreMap[String(rawScore).toLowerCase()] ?? 50);
  const scoreLabel =
    typeof rawScore === "string" ? rawScore : `${rawScore} / 100`;
  const color =
    score >= 75
      ? "var(--green)"
      : score >= 50
        ? "var(--warn)"
        : "var(--danger)";
  const dotClass =
    score >= 75 ? "conf-high" : score >= 50 ? "conf-med" : "conf-low";

  // ── Approve ───────────────────────────────────────────────────────────────
  async function approve() {
    try {
      const response = await fetch(`${API_BASE_URL}/approve`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          doc_id: aiResult.doc_id,
          reviewer_id: "demo_user",
          edited_summary: profText,
          edited_patient: patText,
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

  // ── Main review UI ────────────────────────────────────────────────────────
  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Review &amp; Approve</div>
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

        {/* Confidence Score */}
        <div className="full-width-section" style={{ marginBottom: 20 }}>
          <div className="result-section-title" style={{ marginBottom: 8 }}>
            Confidence Score
          </div>
          <div className="confidence-ring">
            <span className={`conf-dot ${dotClass}`}></span> {scoreLabel}
          </div>
          <div className="confidence-bar-wrap">
            <div className="confidence-bar">
              <div
                className="confidence-bar-fill"
                style={{ width: `${score}%`, background: color }}
              />
            </div>
          </div>
        </div>

        {/* Editable summaries */}
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

        {/* Disclaimer */}
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
