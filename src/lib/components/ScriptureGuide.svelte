<script lang="ts">
  import { livingScrollsData, type LivingScroll, type ScrollPart } from '../livingScrollsData';
  import { authStore } from '../stores/auth';
  import { journalEntries } from '../stores';
  import VoiceRecorder from './VoiceRecorder.svelte';
  
  let scenario = '';
  let loading = false;
  let scriptures: Array<{verse: string, text: string, application: string}> = [];
  let history: Array<{scenario: string, scriptures: typeof scriptures}> = [];
  let encouragement = '';
  let useAI = true; // Toggle between AI and keyword matching
  let showGuidanceModal = false; // Show popup modal for AI guidance
  
  let selectedScroll: LivingScroll | null = null;
  let selectedPart: ScrollPart | null = null;
  let expandedParts: Set<number> = new Set();
  
  // Get recent journal entry for context
  $: recentEntry = $journalEntries[0];
  $: if (recentEntry && scenario === '') {
    // Suggest guidance based on recent journal mood
    if (recentEntry.mood === 'anxious' || recentEntry.mood === 'troubled') {
      scenario = `I'm feeling ${recentEntry.mood}...`;
    }
  }
  
  function togglePart(index: number) {
    if (expandedParts.has(index)) {
      expandedParts.delete(index);
    } else {
      expandedParts.add(index);
    }
    expandedParts = expandedParts;
  }
  
  function selectScroll(scroll: LivingScroll) {
    selectedScroll = scroll;
    scenario = '';
    scriptures = [];
  }
  
  function closeScroll() {
    selectedScroll = null;
  }
  
  // Scripture database for keyword matching
  const scriptureDatabase = {
    anxiety: [
      {
        verse: "Philippians 4:6-7",
        text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
        keywords: ["anxious", "worry", "stressed", "nervous", "afraid", "fear"]
      },
      {
        verse: "1 Peter 5:7",
        text: "Cast all your anxiety on him because he cares for you.",
        keywords: ["anxious", "worry", "burden", "care"]
      }
    ],
    strength: [
      {
        verse: "Isaiah 40:31",
        text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
        keywords: ["tired", "weak", "exhausted", "strength", "weary", "give up"]
      },
      {
        verse: "Philippians 4:13",
        text: "I can do all this through him who gives me strength.",
        keywords: ["impossible", "hard", "difficult", "strength", "challenge"]
      }
    ]
  };
  
  function findRelevantScriptures(text: string) {
    const words = text.toLowerCase().split(/\s+/);
    const matches: Array<{verse: string, text: string, score: number, application: string}> = [];
    
    Object.values(scriptureDatabase).forEach(category => {
      category.forEach(scripture => {
        let score = 0;
        
        scripture.keywords.forEach(keyword => {
          if (text.toLowerCase().includes(keyword)) {
            score += 2;
          }
          words.forEach(word => {
            if (keyword.includes(word) || word.includes(keyword)) {
              score += 1;
            }
          });
        });
        
        if (score > 0) {
          matches.push({
            verse: scripture.verse,
            text: scripture.text,
            score,
            application: generateApplication(text, scripture.verse)
          });
        }
      });
    });
    
    return matches
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
      .map(({verse, text, application}) => ({verse, text, application}));
  }
  
  function generateApplication(scenario: string, verse: string) {
    const applications: Record<string, string> = {
      "Philippians 4:6-7": "In this situation, God invites you to bring your concerns to Him in prayer. He promises His peace will guard your heart.",
      "1 Peter 5:7": "God cares deeply about what you're going through. You can trust Him with this burden.",
      "Isaiah 40:31": "Wait on the Lord. He will renew your strength for the challenges ahead.",
      "Philippians 4:13": "You can face this through Christ's strength, not your own."
    };
    
    return applications[verse] || "God's Word speaks directly to your situation. Meditate on this verse and let it guide you.";
  }
  
  async function getAIGuidance(situation: string) {
    try {
      const response = await fetch('/api/guidance', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          situation,
          mood: recentEntry?.mood,
          recentJournalContent: recentEntry?.content
        })
      });

      const data = await response.json();
      
      if (data.success && data.guidance) {
        return data.guidance;
      } else {
        // Use the fallback guidance from the API
        return data.guidance || null;
      }
    } catch (error) {
      console.error('AI Guidance error:', error);
      // Return null to trigger local fallback
      return null;
    }
  }

  async function handleSubmit() {
    if (!scenario.trim()) return;
    
    loading = true;
    
    if (useAI) {
      // Use AI for intelligent guidance
      const aiGuidance = await getAIGuidance(scenario);
      
      if (aiGuidance) {
        scriptures = aiGuidance.verses.map(v => ({
          verse: v.reference,
          text: v.text,
          application: v.application
        }));
        encouragement = aiGuidance.encouragement;
        showGuidanceModal = true; // Show popup modal
      } else {
        // Fallback to keyword matching if AI fails
        const relevantScriptures = findRelevantScriptures(scenario);
        scriptures = relevantScriptures.length > 0 ? relevantScriptures : [{
          verse: "Jeremiah 29:11",
          text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
          application: "Even when the path is unclear, God has good plans for you. Trust in His timing and purpose."
        }];
        showGuidanceModal = true;
      }
    } else {
      // Use traditional keyword matching
      const relevantScriptures = findRelevantScriptures(scenario);
      
      if (relevantScriptures.length === 0) {
        scriptures = [
          {
            verse: "Jeremiah 29:11",
            text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
            application: "Even when the path is unclear, God has good plans for you. Trust in His timing and purpose."
          }
        ];
      } else {
        scriptures = relevantScriptures;
      }
      showGuidanceModal = true;
    }
    
    history = [{scenario, scriptures}, ...history].slice(0, 5);
    loading = false;
  }
  
  function reset() {
    scenario = '';
    scriptures = [];
    showGuidanceModal = false;
  }
  
  function closeGuidanceModal() {
    showGuidanceModal = false;
  }
  
  function handleVoiceTranscription(event: CustomEvent) {
    const { text } = event.detail;
    scenario = scenario ? `${scenario} ${text}` : text;
  }
  
  function handleVoiceError(event: CustomEvent) {
    console.error('Voice recording error:', event.detail.message);
    alert(event.detail.message);
  }
</script>

<div class="scripture-guide">
  <div class="guide-header">
    <h2>📜 Living Scrolls Scripture Library</h2>
    <p class="subtitle">43 Life Situations Answered with Pure Scripture</p>
  </div>
  
  <div class="input-section">
    <h3>🌟 Ask for Personalized Guidance</h3>
    <div class="ai-toggle">
      <label class="toggle-label">
        <input type="checkbox" bind:checked={useAI} />
        <span class="toggle-text">
          {useAI ? '✨ AI-Powered Guidance' : '📖 Keyword Matching'}
        </span>
      </label>
      <small class="toggle-hint">
        {useAI ? 'Get personalized scripture, prayer, and action steps' : 'Quick scripture matching based on keywords'}
      </small>
    </div>
    
    <div class="input-with-voice">
      <textarea
        bind:value={scenario}
        placeholder={useAI 
          ? "Share what's on your heart, and I'll provide scripture, prayer, and guidance..." 
          : "Describe what you're going through and receive scripture guidance..."}
        rows="4"
        disabled={loading}
      ></textarea>
      <div class="voice-button-wrapper">
        <VoiceRecorder
          placeholder="Speak your situation..."
          on:transcription={handleVoiceTranscription}
          on:error={handleVoiceError}
        />
      </div>
    </div>
    
    <button 
      class="submit-btn" 
      on:click={handleSubmit}
      disabled={loading || !scenario.trim()}
    >
      {loading ? 'Finding Scriptures...' : 'Get Scripture Guidance'}
    </button>
  </div>
  
  <div class="divider">
    <span>or browse the complete library below</span>
  </div>
  
  <div class="scrolls-container">
    {#each livingScrollsData as part, partIndex}
      <div class="part-section">
        <button 
          class="part-header"
          on:click={() => togglePart(partIndex)}
        >
          <span class="part-title">
            {expandedParts.has(partIndex) ? '▼' : '▶'} {part.title}
          </span>
          <span class="scroll-count">({part.scrolls.length} scrolls)</span>
        </button>
        
        {#if expandedParts.has(partIndex)}
          <div class="scrolls-grid">
            {#each part.scrolls as scroll}
              <button 
                class="scroll-btn" 
                on:click={() => selectScroll(scroll)}
              >
                {scroll.title}
              </button>
            {/each}
          </div>
        {/if}
      </div>
    {/each}
  </div>
  
  {#if showGuidanceModal && scriptures.length > 0}
    <div class="guidance-overlay" on:click={closeGuidanceModal}>
      <div class="guidance-modal" on:click|stopPropagation>
        <button class="close-btn" on:click={closeGuidanceModal}>✕</button>
        <h2 class="modal-title">✨ Scripture Guidance for You</h2>
        
        <div class="modal-content">
          <h3>God's Word for Your Situation:</h3>
          
          {#each scriptures as scripture}
            <div class="scripture-card">
              <div class="verse-header">
                <span class="verse-ref">📖 {scripture.verse}</span>
              </div>
              
              <blockquote class="verse-text">
                "{scripture.text}"
              </blockquote>
              
              <div class="application">
                <strong>Application:</strong>
                <p>{scripture.application}</p>
              </div>
            </div>
          {/each}
          
          {#if encouragement}
            <div class="encouragement-card">
              <div class="card-header">
                <span class="card-icon">💛</span>
                <h4>Encouragement</h4>
              </div>
              <p class="encouragement-text">{encouragement}</p>
            </div>
          {/if}
        </div>
        
        <button class="new-btn" on:click={reset}>
          Ask About Something Else
        </button>
      </div>
    </div>
  {/if}
  
  {#if selectedScroll}
    <div class="scroll-overlay" on:click={closeScroll}>
      <div class="scroll-content" on:click|stopPropagation>
        <button class="close-btn" on:click={closeScroll}>✕</button>
        <h2 class="scroll-title">📜 {selectedScroll.title}</h2>
        
        <div class="scroll-text">
          <p class="scripture-paragraph">
            {selectedScroll.scroll}
          </p>
          
          <div class="references">
            {selectedScroll.references}
          </div>
        </div>
        
        <div class="application-section">
          <h4>Application:</h4>
          <p>{selectedScroll.application}</p>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .scripture-guide {
    max-width: 900px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .guide-header {
    text-align: center;
    margin-bottom: 2rem;
  }
  
  .guide-header h2 {
    margin: 0 0 0.5rem 0;
    color: #333;
  }
  
  .subtitle {
    color: #666;
    margin: 0;
  }
  
  .scrolls-container {
    margin-bottom: 2rem;
  }
  
  .part-section {
    margin-bottom: 1rem;
    background: white;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  }
  
  .part-header {
    width: 100%;
    padding: 1rem 1.5rem;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    cursor: pointer;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 1.1rem;
    font-weight: 600;
    transition: all 0.2s;
  }
  
  .part-header:hover {
    filter: brightness(1.1);
  }
  
  .part-title {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .scroll-count {
    font-size: 0.9rem;
    opacity: 0.9;
  }
  
  .scrolls-grid {
    padding: 1rem;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 0.75rem;
    background: #f8f9fa;
  }
  
  .scroll-btn {
    padding: 0.75rem 1rem;
    background: white;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    text-align: left;
    font-size: 0.95rem;
    color: #555;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .scroll-btn:hover {
    border-color: #667eea;
    background: #f8f9ff;
    transform: translateY(-2px);
    box-shadow: 0 2px 8px rgba(102, 126, 234, 0.2);
  }
  
  .divider {
    text-align: center;
    margin: 2rem 0;
    position: relative;
  }
  
  .divider::before {
    content: '';
    position: absolute;
    top: 50%;
    left: 0;
    right: 0;
    height: 1px;
    background: #e0e0e0;
  }
  
  .divider span {
    background: #f5f7fa;
    padding: 0 1rem;
    color: #999;
    position: relative;
  }
  
  .input-section {
    background: white;
    padding: 1.5rem;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    margin-bottom: 2rem;
  }
  
  .input-section h3 {
    color: #667eea;
    margin: 0 0 1rem 0;
  }
  
  textarea {
    width: 100%;
    padding: 1rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1rem;
    font-family: inherit;
    resize: vertical;
    transition: border-color 0.2s;
  }
  
  textarea:focus {
    outline: none;
    border-color: #667eea;
  }
  
  .submit-btn {
    width: 100%;
    padding: 1rem;
    margin-top: 1rem;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .submit-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
  }
  
  .submit-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  
  .scriptures-section {
    margin-bottom: 2rem;
  }
  
  .scriptures-section h3 {
    color: #333;
    margin-bottom: 1rem;
  }
  
  .scripture-card {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 1rem;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    border-left: 4px solid #667eea;
  }
  
  .prayer-card, .action-card, .encouragement-card {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.05), rgba(138, 43, 226, 0.05));
    border: 1px solid rgba(255, 215, 0, 0.3);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 1rem;
    box-shadow: 0 2px 8px rgba(255, 215, 0, 0.1);
  }
  
  .prayer-card {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.05));
    border-color: rgba(138, 43, 226, 0.3);
  }
  
  .action-card {
    background: linear-gradient(135deg, rgba(76, 175, 80, 0.05), rgba(255, 215, 0, 0.05));
    border-color: rgba(76, 175, 80, 0.3);
  }
  
  .encouragement-card {
    background: linear-gradient(135deg, rgba(255, 193, 7, 0.05), rgba(255, 87, 34, 0.05));
    border-color: rgba(255, 193, 7, 0.3);
  }
  
  .card-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 1rem;
  }
  
  .card-header h4 {
    margin: 0;
    color: #4a5568;
    font-size: 1.1rem;
  }
  
  .card-icon {
    font-size: 1.5rem;
  }
  
  .prayer-text, .action-text, .encouragement-text {
    color: #2d3748;
    line-height: 1.6;
    font-size: 0.95rem;
  }
  
  .prayer-text {
    font-style: italic;
  }
  
  .ai-toggle {
    margin-bottom: 1rem;
    padding: 1rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(255, 215, 0, 0.05));
    border-radius: 8px;
    border: 1px solid rgba(138, 43, 226, 0.2);
  }
  
  .toggle-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    font-weight: 600;
    color: #4a5568;
  }
  
  .toggle-label input[type="checkbox"] {
    width: 20px;
    height: 20px;
    cursor: pointer;
  }
  
  .toggle-text {
    font-size: 1rem;
  }
  
  .toggle-hint {
    display: block;
    margin-top: 0.5rem;
    margin-left: 1.75rem;
    color: #718096;
    font-size: 0.85rem;
  }
  
  .input-with-voice {
    position: relative;
  }
  
  .voice-button-wrapper {
    position: absolute;
    bottom: 10px;
    right: 10px;
    background: rgba(245, 247, 250, 0.95);
    border-radius: 50%;
    padding: 5px;
  }
  
  .verse-header {
    margin-bottom: 1rem;
  }
  
  .verse-ref {
    color: #667eea;
    font-weight: 600;
    font-size: 1.1rem;
  }
  
  .verse-text {
    font-style: italic;
    color: #444;
    line-height: 1.8;
    margin: 1rem 0;
    padding-left: 1rem;
    border-left: 2px solid #e0e0e0;
  }
  
  .application {
    background: #f8f9fa;
    padding: 1rem;
    border-radius: 8px;
    margin-top: 1rem;
  }
  
  .application strong {
    color: #667eea;
    display: block;
    margin-bottom: 0.5rem;
  }
  
  .application p {
    margin: 0;
    color: #555;
    line-height: 1.6;
  }
  
  .new-btn {
    width: 100%;
    padding: 0.75rem;
    background: #27ae60;
    color: white;
    border: none;
    border-radius: 8px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .new-btn:hover {
    background: #229954;
  }
  
  .guidance-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.8);
    backdrop-filter: blur(5px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1001;
    padding: 1rem;
    animation: fadeIn 0.3s ease-in-out;
  }
  
  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }
  
  .guidance-modal {
    background: linear-gradient(135deg, #fff 0%, #f8f9ff 100%);
    border-radius: 20px;
    max-width: 800px;
    width: 100%;
    max-height: 90vh;
    overflow-y: auto;
    padding: 2.5rem;
    position: relative;
    box-shadow: 0 20px 60px rgba(102, 126, 234, 0.3), 0 0 100px rgba(255, 215, 0, 0.1);
    animation: slideUp 0.4s ease-out;
  }
  
  @keyframes slideUp {
    from {
      transform: translateY(30px);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }
  
  .modal-title {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    font-size: 2rem;
    margin: 0 0 2rem 0;
    font-weight: 700;
  }
  
  .modal-content {
    margin-bottom: 1.5rem;
  }
  
  .modal-content h3 {
    color: #4a5568;
    margin-bottom: 1.5rem;
    font-size: 1.2rem;
  }
  
  .scroll-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: 1rem;
  }
  
  .scroll-content {
    background: white;
    border-radius: 12px;
    max-width: 700px;
    width: 100%;
    max-height: 90vh;
    overflow-y: auto;
    padding: 2rem;
    position: relative;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
  }
  
  .close-btn {
    position: absolute;
    top: 1rem;
    right: 1rem;
    background: none;
    border: none;
    font-size: 1.5rem;
    color: #999;
    cursor: pointer;
    padding: 0.5rem;
    line-height: 1;
    transition: color 0.2s;
  }
  
  .close-btn:hover {
    color: #333;
  }
  
  .scroll-title {
    color: #667eea;
    margin: 0 0 1.5rem 0;
    font-size: 1.5rem;
    text-align: center;
  }
  
  .scroll-text {
    background: #f8f9fa;
    padding: 1.5rem;
    border-radius: 8px;
    margin-bottom: 1.5rem;
    border-left: 4px solid #667eea;
  }
  
  .scripture-paragraph {
    font-size: 1.1rem;
    line-height: 1.8;
    color: #333;
    margin: 0 0 1rem 0;
    font-family: 'Georgia', 'Times New Roman', serif;
  }
  
  .references {
    font-size: 0.9rem;
    color: #666;
    font-style: italic;
    padding-top: 1rem;
    border-top: 1px solid #e0e0e0;
  }
  
  .application-section {
    background: #fff8e1;
    padding: 1rem;
    border-radius: 8px;
    border-left: 4px solid #ffc107;
  }
  
  .application-section h4 {
    color: #f57c00;
    margin: 0 0 0.75rem 0;
    font-size: 1.1rem;
  }
  
  .application-section p {
    color: #555;
    line-height: 1.6;
    margin: 0;
  }
  
  @media (max-width: 600px) {
    .scrolls-grid {
      grid-template-columns: 1fr;
    }
    
    .scroll-content {
      padding: 1.5rem;
    }
    
    .guidance-modal {
      padding: 1.5rem;
      margin: 1rem;
    }
    
    .modal-title {
      font-size: 1.5rem;
    }
    
    .scripture-paragraph {
      font-size: 1rem;
    }
  }
</style>