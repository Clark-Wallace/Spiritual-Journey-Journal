export default async function handler(req, res) {
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
    if (!process.env.OPENAI_API_KEY) {
      console.error('Missing OPENAI_API_KEY environment variable');
      return res.status(500).json({ 
        error: 'API configuration error',
        message: 'OpenAI API key not configured'
      });
    }

    // Get the audio data from the request
    const { audio } = req.body;
    
    if (!audio) {
      return res.status(400).json({ error: 'Audio data is required' });
    }

    // Convert base64 audio to blob
    const audioBlob = Buffer.from(audio, 'base64');
    
    // Create form data for Whisper API
    const formData = new FormData();
    formData.append('file', new Blob([audioBlob], { type: 'audio/webm' }), 'audio.webm');
    formData.append('model', 'whisper-1');
    formData.append('language', 'en');
    
    console.log('Calling Whisper API...');
    
    // Call OpenAI Whisper API
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: formData
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Whisper API error:', response.status, errorText);
      throw new Error(`Whisper API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    
    return res.status(200).json({
      success: true,
      text: data.text,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Transcription API error:', error.message || error);
    
    return res.status(500).json({
      success: false,
      error: error.message || 'Transcription failed',
      timestamp: new Date().toISOString()
    });
  }
}