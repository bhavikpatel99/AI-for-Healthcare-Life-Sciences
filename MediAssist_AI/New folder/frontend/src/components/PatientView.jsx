export function PatientView({ result }) {
  if (!result) {
    return (
      <section className="panel placeholder">
        <h2>Patient-friendly Explanation</h2>
        <p>After you run an analysis, a patient-ready explanation will appear here for review and editing.</p>
      </section>
    )
  }

  const { patientExplanation } = result

  return (
    <section className="panel">
      <h2>Patient-friendly Explanation</h2>
      <p className="helper">
        This explanation is intended for patients and caregivers. Review carefully and edit as needed before sharing.
      </p>

      <textarea
        className="textarea"
        rows={14}
        defaultValue={patientExplanation}
      />

      <div className="actions-row">
        <button type="button" className="secondary-button">
          Copy to clipboard
        </button>
      </div>
    </section>
  )
}

