import { useEffect, useState } from "react";
import { useApp } from "../context/AppContext";

// ✅ Fix 1: Reduced to 3 steps — step 2 now only lasts ~1s (just the upload)
// Old: 6 fake steps over 4.5s — panel was cut off before finishing
// New: 3 fast steps over 1.2s — completes cleanly before step 3 kicks in
const loadingSteps = [
  "Uploading to secure storage…",
  "Validating document content…",
  "Sending to AI for analysis…",
];

const ProcessingPanel = () => {
  const { currentStep } = useApp();
  const [activeStep, setActiveStep] = useState(0);

  useEffect(() => {
    if (currentStep !== 2) return;

    setActiveStep(0);

    // ✅ Fix 2: Fast delays — match real upload time (~1s)
    const delays = [0, 400, 800];
    const timers = delays.map((delay, i) =>
      setTimeout(() => setActiveStep(i), delay)
    );

    return () => timers.forEach(clearTimeout);
  }, [currentStep]);

  if (currentStep !== 2) return null;

  return (
    <div className="panel active">
      <div className="card">
        <div className="card-title">Uploading Document</div>
        <div className="card-subtitle">
          Securely uploading your document for AI analysis…
        </div>

        <div className="loading-overlay active">
          <div className="spinner"></div>
          <div className="loading-text">Uploading…</div>

          <div className="loading-steps">
            {loadingSteps.map((label, i) => (
              <div
                key={i}
                className={`loading-step ${i === activeStep ? "active" : ""} ${i < activeStep ? "done" : ""}`}
              >
                <span className="loading-step-dot"></span>
                {label}
              </div>
            ))}
          </div>

          {/* ✅ Fix 3: Inform user AI processing happens on next screen */}
          <div style={{
            marginTop: 24,
            fontSize: 12,
            color: "var(--text-dim)",
            textAlign: "center"
          }}>
            AI analysis will begin on the next screen
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProcessingPanel;