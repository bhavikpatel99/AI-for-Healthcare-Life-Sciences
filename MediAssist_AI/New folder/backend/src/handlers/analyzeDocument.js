const { analyzeDocument } = require('../analysisService')

async function handler(event) {
  try {
    const body = event.body ? JSON.parse(event.body) : {}
    const { text, sourceType, filename, audience } = body

    if (!text || typeof text !== 'string') {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ message: 'text is required' })
      }
    }

    const result = await analyzeDocument({ text, audience })

    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: JSON.stringify({
        ...result,
        sourceType: sourceType || 'text',
        filename: filename || null
      })
    }
  } catch (error) {
    console.error('Analyze error', error)

    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: JSON.stringify({ message: 'Internal error during analysis' })
    }
  }
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'OPTIONS,POST'
  }
}

module.exports = { handler }

