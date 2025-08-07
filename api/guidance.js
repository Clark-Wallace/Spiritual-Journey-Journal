import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { situation, mood, recentJournalContent } = req.body;

    // Build context from journal if available
    let context = '';
    if (mood) {
      context += `The person is feeling ${mood}. `;
    }
    if (recentJournalContent) {
      context += `Recent reflection: "${recentJournalContent}" `;
    }

    const prompt = `You are a compassionate Christian counselor providing biblical guidance. 

User's situation: "${situation}"
${context ? `Context: ${context}` : ''}

Please provide:
1. 2-3 relevant Bible verses that directly address this situation
2. A brief explanation of why each verse applies
3. A short prayer for their situation
4. One practical action step rooted in scripture

Format your response as JSON:
{
  "verses": [
    {
      "reference": "verse reference",
      "text": "verse text",
      "application": "why this applies"
    }
  ],
  "prayer": "personalized prayer",
  "actionStep": "practical guidance",
  "encouragement": "brief encouraging word"
}`;

    const response = await anthropic.messages.create({
      model: 'claude-3-haiku-20240307', // Fast and cost-effective for this use case
      max_tokens: 1000,
      temperature: 0.7,
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ]
    });

    // Parse the response
    const guidanceText = response.content[0].text;
    const guidance = JSON.parse(guidanceText);

    res.status(200).json({
      success: true,
      guidance,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Guidance API error:', error);
    res.status(500).json({ 
      error: 'Failed to get guidance',
      message: error.message 
    });
  }
}