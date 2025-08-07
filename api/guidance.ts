export default async function handler(req: any, res: any) {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Enable CORS
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  try {
    // Check if API key exists
    if (!process.env.ANTHROPIC_API_KEY) {
      console.error('Missing ANTHROPIC_API_KEY environment variable');
      return res.status(500).json({ 
        error: 'API configuration error',
        message: 'Claude API key not configured'
      });
    }

    const { situation, mood, recentJournalContent } = req.body;
    
    if (!situation) {
      return res.status(400).json({ error: 'Situation is required' });
    }

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
1. 2-3 relevant Bible verses that directly address this situation (use well-known translations like NIV or ESV)
2. A brief explanation of why each verse applies to their specific situation
3. A short, heartfelt prayer for their situation
4. One practical action step rooted in scripture
5. A brief encouraging word

Format your response as JSON:
{
  "verses": [
    {
      "reference": "Book Chapter:Verse",
      "text": "The actual verse text",
      "application": "2-3 sentences on why this verse specifically applies to their situation"
    }
  ],
  "prayer": "A personal prayer addressing their specific situation",
  "actionStep": "One practical thing they can do today",
  "encouragement": "A brief, uplifting message of hope"
}

Ensure the response is compassionate, specific to their situation, and grounded in biblical truth.`;

    console.log('Calling Claude API with key starting:', process.env.ANTHROPIC_API_KEY ? 'Key exists' : 'KEY MISSING');
    
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY!,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-3-5-haiku-20241022',  // Latest Haiku 3.5 - fast and affordable
        max_tokens: 1500,
        temperature: 0.7,
        messages: [
          {
            role: 'user',
            content: prompt
          }
        ]
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Claude API error:', response.status, errorText);
      throw new Error(`Claude API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    
    // Extract the text content from Claude's response
    const responseText = data.content[0].text;
    
    // Parse the JSON from Claude's response
    let guidance;
    try {
      // Find JSON in the response (Claude might add explanation text)
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        guidance = JSON.parse(jsonMatch[0]);
      } else {
        throw new Error('No JSON found in response');
      }
    } catch (parseError) {
      console.error('Failed to parse Claude response:', responseText);
      // Fallback response
      guidance = {
        verses: [
          {
            reference: "Philippians 4:6-7",
            text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.",
            application: "God invites you to bring your specific concerns to Him right now."
          }
        ],
        prayer: "Lord, please provide wisdom and peace in this situation. Amen.",
        actionStep: "Take 5 minutes to pray and cast your cares on God.",
        encouragement: "God is with you in this. You are not alone."
      };
    }

    return res.status(200).json({
      success: true,
      guidance,
      timestamp: new Date().toISOString()
    });

  } catch (error: any) {
    console.error('Guidance API error:', error.message || error);
    
    // Log more details for debugging
    if (error.message?.includes('Claude API error')) {
      console.error('Claude API specific error - check API key and model name');
    }
    
    // Always return a valid response with fallback guidance
    return res.status(200).json({
      success: false,
      guidance: {
        verses: [
          {
            reference: "Proverbs 3:5-6",
            text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
            application: "Even when things are unclear, God promises to guide you as you trust Him."
          },
          {
            reference: "Philippians 4:19",
            text: "And my God will meet all your needs according to the riches of his glory in Christ Jesus.",
            application: "God knows your needs and will provide in His perfect timing."
          }
        ],
        prayer: "Lord, grant wisdom and peace in this challenging time. Guide each step with Your love. Amen.",
        actionStep: "Spend 10 minutes in quiet prayer, sharing your heart with God.",
        encouragement: "God sees you, loves you, and is working all things for your good."
      },
      error: error.message || 'Using fallback guidance',
      debugInfo: process.env.NODE_ENV === 'development' ? error.toString() : undefined,
      timestamp: new Date().toISOString()
    });
  }
}