import Header from './components/Header'
import Footer from './components/Footer'
import StepIndicator from './components/StepIndicator'

import UploadPanel from './panels/UploadPanel'
import ProcessingPanel from './panels/ProcessingPanel'
import ReviewPanel from './panels/ReviewPanel'
import ExportPanel from './panels/ExportPanel'

import { useApp } from './context/AppContext'

function App() {
  const { currentStep } = useApp()

  return (
    <div className="app">

      <Header />

      <main className="main">
        <div className="container">

          <StepIndicator />

          <div className="panels">
            {currentStep === 1 && <UploadPanel />}
            {currentStep === 2 && <ProcessingPanel />}
            {currentStep === 3 && <ReviewPanel />}
            {currentStep === 4 && <ExportPanel />}
          </div>

        </div>
      </main>

      <Footer />

    </div>
  )
}

export default App