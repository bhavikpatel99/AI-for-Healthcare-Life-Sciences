const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime')

const REGION = process.env.AWS_REGION || process.env.BEDROCK_REGION || 'us-east-1'
const MODEL_ID = process.env.BEDROCK_MODEL_ID || 'anthropic.claude-3-haiku-20240307-v1:0'

const client = new BedrockRuntimeClient({ region: REGION })

async function invokeModel(prompt) {
  const payload = {
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: prompt
          }
        ]
      }
    ],
    inferenceConfig: {
      maxTokens: 1200,
      temperature: 0.2
    }
  }

  const command = new InvokeModelCommand({
    modelId: MODEL_ID,
    contentType: 'application/json',
    accept: 'application/json',
    body: Buffer.from(JSON.stringify(payload))
  })

  const response = await client.send(command)
  const decoded = JSON.parse(Buffer.from(response.body).toString('utf8'))
  const text = decoded.output?.message?.content?.[0]?.text || ''
  return text
}

module.exports = {
  invokeModel
}

