<script lang="ts">
  import { journalEntries } from '../stores';
  import { shareToCommunity } from '../supabase';
  import type { JournalEntry } from '../types';
  
  let mood: JournalEntry['mood'] = undefined;
  let gratitude = ['', '', ''];
  let content = '';
  let prayer = '';
  let savePrayer = false;
  let shareToFeed = false;
  let shareType: 'post' | 'prayer' | 'testimony' | 'praise' = 'post';
  let shareAnonymously = false;
  
  const moods: JournalEntry['mood'][] = [
    'grateful', 'peaceful', 'joyful', 'hopeful', 
    'reflective', 'troubled', 'anxious', 'seeking'
  ];
  
  const moodEmojis = {
    grateful: '🙏',
    peaceful: '😌',
    joyful: '😊',
    hopeful: '✨',
    reflective: '🤔',
    troubled: '😟',
    anxious: '😰',
    seeking: '🔍'
  };
  
  async function handleSubmit() {
    const validGratitude = gratitude.filter(g => g.trim());
    
    if (!mood && validGratitude.length === 0 && !content && (!prayer || !savePrayer)) {
      alert('Please add something to your journal entry');
      return;
    }
    
    try {
      const journalEntry = await journalEntries.addEntry({
        date: new Date(),
        mood,
        gratitude: validGratitude,
        content,
        prayer: savePrayer ? prayer : '' // Only save prayer if checkbox is checked
      });
      
      // If sharing to community feed
      if (shareToFeed) {
        try {
          const communityPost = await shareToCommunity({
            mood,
            gratitude: validGratitude,
            content,
            prayer: savePrayer ? prayer : '',
            shareType,
            isAnonymous: shareAnonymously
          });
          
          // Show specific feedback for sharing
          if (communityPost) {
            alert('Entry saved to your journal and shared with the community! 🎉✨');
          } else {
            alert('Entry saved to your journal, but sharing failed. Try sharing from Community later.');
          }
        } catch (shareError) {
          console.error('Error sharing to community:', shareError);
          alert(`Entry saved to journal, but sharing failed: ${shareError.message}`);
        }
      } else {
        alert('Entry saved to your private journal! 📔');
      }
      
      // Reset form
      mood = undefined;
      gratitude = ['', '', ''];
      content = '';
      prayer = '';
      savePrayer = false;
      shareToFeed = false;
      shareType = 'post';
      shareAnonymously = false;
    } catch (error) {
      console.error('Error saving entry:', error);
      alert('Failed to save entry. Please try again.');
    }
  }
</script>

<div class="journal-form-illuminated">
  <div class="form-header">
    <div class="header-glow">📔</div>
    <h2>Sacred Journal Entry</h2>
    <p class="header-verse">Write it down, make it plain - Habakkuk 2:2</p>
  </div>
  
  <div class="form-section">
    <label class="section-label">How is your soul today?</label>
    <div class="mood-grid">
      {#each moods as m}
        <button
          class="mood-btn"
          class:selected={mood === m}
          on:click={() => mood = m}
        >
          <span class="emoji">{moodEmojis[m]}</span>
          <span class="label">{m}</span>
        </button>
      {/each}
    </div>
  </div>
  
  <div class="form-section">
    <label class="section-label">Count your blessings - What are you grateful for?</label>
    {#each gratitude as item, i}
      <input
        type="text"
        class="gratitude-input"
        placeholder="Blessing #{i + 1}"
        bind:value={gratitude[i]}
      />
    {/each}
  </div>
  
  <div class="form-section">
    <label class="section-label">Pour out your heart</label>
    <textarea
      class="journal-textarea"
      placeholder="What's on your heart today? Let it flow..."
      bind:value={content}
      rows="4"
    ></textarea>
  </div>
  
  <div class="form-section prayer-section">
    <label class="section-label">
      <span class="prayer-icon">🙏</span>
      Prayer Corner
    </label>
    <textarea
      class="prayer-textarea"
      placeholder="Talk to God... This sacred space is between you and Him"
      bind:value={prayer}
      rows="3"
    ></textarea>
    <div class="prayer-option">
      <label class="checkbox-label">
        <input 
          type="checkbox" 
          bind:checked={savePrayer}
        />
        <span>Save this prayer with my journal entry</span>
      </label>
      <small class="prayer-note">
        {#if !savePrayer}
          🕊️ Your prayer ascends to heaven but won't be saved in your journal
        {:else}
          📜 Your prayer will be preserved to reflect on God's faithfulness
        {/if}
      </small>
    </div>
  </div>
  
  <div class="form-section sharing-section">
    <label class="section-title">
      <input 
        type="checkbox" 
        bind:checked={shareToFeed}
      />
      <span>Share with the Fellowship</span>
    </label>
    
    {#if shareToFeed}
      <div class="sharing-options">
        <div class="share-type">
          <label>Share as:</label>
          <select bind:value={shareType} class="share-select">
            <option value="post">💭 Thought</option>
            <option value="prayer">🙏 Prayer Request</option>
            <option value="testimony">✨ Testimony</option>
            <option value="praise">🎉 Praise Report</option>
          </select>
        </div>
        
        <label class="checkbox-label">
          <input 
            type="checkbox" 
            bind:checked={shareAnonymously}
          />
          <span>Share as Anonymous Soul</span>
        </label>
        
        <small class="share-note">
          ⚠️ When shared, your entry will be visible to all community members for prayer and encouragement
        </small>
      </div>
    {/if}
  </div>
  
  <button class="submit-btn" on:click={handleSubmit}>
    <span class="btn-text">{shareToFeed ? '📤 Save & Share' : '💾 Save Entry'}</span>
    <span class="btn-subtext">2 minute daily goal</span>
  </button>
</div>

<style>
  .journal-form-illuminated {
    max-width: 700px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .form-header {
    text-align: center;
    margin-bottom: 2rem;
    padding: 1.5rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    position: relative;
    overflow: hidden;
  }
  
  .form-header::before {
    content: '';
    position: absolute;
    top: -50%;
    left: -50%;
    width: 200%;
    height: 200%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.05) 0%, transparent 70%);
    animation: rotate 20s linear infinite;
  }
  
  @keyframes rotate {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
  
  .header-glow {
    font-size: 3rem;
    margin-bottom: 0.5rem;
    filter: drop-shadow(0 0 20px rgba(255, 215, 0, 0.5));
    animation: float 3s ease-in-out infinite;
  }
  
  @keyframes float {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
  }
  
  .form-header h2 {
    color: var(--text-divine);
    margin: 0 0 0.5rem 0;
    font-family: var(--font-primary);
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
    position: relative;
    z-index: 1;
  }
  
  .header-verse {
    color: var(--text-scripture);
    font-style: italic;
    font-size: 0.9rem;
    position: relative;
    z-index: 1;
  }
  
  .form-section {
    margin-bottom: 2rem;
    padding: 1.5rem;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 10px;
    backdrop-filter: blur(10px);
  }
  
  .section-label {
    display: block;
    margin-bottom: 1rem;
    font-weight: 600;
    color: var(--text-divine);
    font-size: 1rem;
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.2);
  }
  
  .mood-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0.75rem;
  }
  
  .mood-btn {
    padding: 0.75rem;
    border: 2px solid var(--border-gold);
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.03);
    cursor: pointer;
    transition: all 0.3s;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.25rem;
    color: var(--text-holy);
  }
  
  .mood-btn:hover {
    background: rgba(255, 215, 0, 0.1);
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.2);
  }
  
  .mood-btn.selected {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(30, 144, 255, 0.2));
    border-color: var(--border-gold-strong);
    box-shadow: 0 0 20px rgba(138, 43, 226, 0.3);
  }
  
  .emoji {
    font-size: 1.5rem;
  }
  
  .label {
    font-size: 0.75rem;
    text-transform: capitalize;
    color: var(--text-holy);
  }
  
  input, textarea {
    width: 100%;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    font-size: 1rem;
    margin-bottom: 0.5rem;
    color: var(--text-light);
    font-family: inherit;
    transition: all 0.3s;
  }
  
  input::placeholder, textarea::placeholder {
    color: var(--text-scripture);
  }
  
  input:focus, textarea:focus {
    outline: none;
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--border-gold-strong);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .gratitude-input {
    background: rgba(255, 215, 0, 0.03);
  }
  
  textarea {
    resize: vertical;
    line-height: 1.6;
  }
  
  .prayer-section {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.03));
    border-color: rgba(138, 43, 226, 0.2);
  }
  
  .prayer-icon {
    font-size: 1.2rem;
    margin-right: 0.5rem;
  }
  
  .prayer-textarea {
    background: rgba(138, 43, 226, 0.03);
    border-color: rgba(138, 43, 226, 0.3);
  }
  
  .prayer-option {
    margin-top: 1rem;
  }
  
  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    font-size: 0.95rem;
    color: var(--text-holy);
  }
  
  .checkbox-label input[type="checkbox"] {
    width: auto;
    margin: 0;
    cursor: pointer;
    accent-color: var(--primary-gold);
  }
  
  .prayer-note {
    display: block;
    margin-top: 0.5rem;
    margin-left: 1.5rem;
    color: var(--text-scripture);
    font-style: italic;
    font-size: 0.85rem;
    line-height: 1.4;
  }
  
  .sharing-section {
    background: linear-gradient(135deg, rgba(255, 152, 0, 0.05), rgba(255, 193, 7, 0.03));
    border-color: rgba(255, 152, 0, 0.2);
  }
  
  .section-title {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 600;
    color: var(--text-divine);
    cursor: pointer;
    margin-bottom: 0;
  }
  
  .section-title input[type="checkbox"] {
    width: auto;
    margin: 0;
    cursor: pointer;
    accent-color: var(--primary-gold);
  }
  
  .sharing-options {
    margin-top: 1rem;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.02);
    border-radius: 8px;
    animation: fadeIn 0.3s ease-out;
  }
  
  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
  
  .share-type {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .share-type label {
    color: var(--text-holy);
    font-weight: 500;
  }
  
  .share-select {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 6px;
    color: var(--text-light);
    cursor: pointer;
    font-size: 0.95rem;
  }
  
  .share-note {
    display: block;
    margin-top: 1rem;
    color: var(--text-scripture);
    font-size: 0.85rem;
    line-height: 1.4;
    padding: 0.75rem;
    background: rgba(255, 215, 0, 0.05);
    border-left: 3px solid var(--border-gold);
    border-radius: 4px;
  }
  
  .submit-btn {
    width: 100%;
    padding: 1.25rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 10px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.25rem;
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.3);
  }
  
  .submit-btn:hover {
    background: linear-gradient(135deg, var(--primary-gold-light), #ffc947);
    transform: translateY(-2px);
    box-shadow: var(--shadow-divine-strong);
  }
  
  .btn-text {
    font-size: 1.1rem;
  }
  
  .btn-subtext {
    font-size: 0.85rem;
    opacity: 0.8;
  }
  
  @media (max-width: 600px) {
    .mood-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }
</style>