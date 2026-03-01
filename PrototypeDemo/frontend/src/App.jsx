import { AppProvider, useApp } from './context/AppContext'
import Header from './components/Header'
import Footer from './components/Footer'
import StepIndicator from './components/StepIndicator'
import UploadPanel from './panels/UploadPanel'
import ProcessingPanel from './panels/ProcessingPanel'
import ReviewPanel from './panels/ReviewPanel'
import ExportPanel from './panels/ExportPanel'

function AppContent() {
  const { currentStep } = useApp()

  return (
    <div className="app">
      <Header />
      <main>
        <StepIndicator />
        {currentStep === 1 && <UploadPanel />}
        {currentStep === 2 && <ProcessingPanel />}
        {currentStep === 3 && <ReviewPanel />}
        {currentStep === 4 && <ExportPanel />}
      </main>
      <Footer />
    </div>
  )
}

function App() {
  return (
    <AppProvider>
      <AppContent />
    </AppProvider>
  )
}

export default App