const express = require('express')
const cors = require('cors')
const { analyzeDocument } = require('./analysisService')

const app = express()
const PORT = process.env.PORT || 4000

app.use(cors())
app.use(express.json({ limit: '1mb' }))

app.post('/api/analyze', async (req, res) => {
  try {
    const { text, audience } = req.body || {}
    if (!text || typeof text !== 'string') {
      res.status(400).json({ message: 'text is required' })
      return
    }
    const result = await analyzeDocument({ text, audience })
    res.json(result)
  } catch (error) {
    console.error('Local analyze error', error)
    res.status(500).json({ message: 'Internal error during analysis' })
  }
})

app.listen(PORT, () => {
  console.log(`Local analysis API listening on http://localhost:${PORT}`)
})

