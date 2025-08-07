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
      await journalEntries.addEntry({
        date: new Date(),
        mood,
        gratitude: validGratitude,
        content,
        prayer: savePrayer ? prayer : '' // Only save prayer if checkbox is checked
      });
      
      // If sharing to community feed
      if (shareToFeed) {
        await shareToCommunity({
          mood,
          gratitude: validGratitude,
          content,
          prayer: savePrayer ? prayer : '',
          shareType,
          isAnonymous: shareAnonymously
        });
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
      
      alert('Entry saved! 🎉');
    } catch (error) {
      console.error('Error saving entry:', error);
      alert('Failed to save entry. Please try again.');
    }
  }
</script>

<div class="journal-form">
  <h2>New Journal Entry</h2>
  
  <div class="form-section">
    <label>How are you feeling?</label>
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
    <label>What are you grateful for?</label>
    {#each gratitude as item, i}
      <input
        type="text"
        placeholder="Gratitude #{i + 1}"
        bind:value={gratitude[i]}
      />
    {/each}
  </div>
  
  <div class="form-section">
    <label>Your thoughts</label>
    <textarea
      placeholder="What's on your heart today?"
      bind:value={content}
      rows="4"
    ></textarea>
  </div>
  
  <div class="form-section">
    <label>Prayer</label>
    <textarea
      placeholder="Talk to God... (This space is for you and God)"
      bind:value={prayer}
      rows="3"
    ></textarea>
    <div class="prayer-option">
      <label class="checkbox-label">
        <input 
          type="checkbox" 
          bind:checked={savePrayer}
        />
        Save this prayer with my journal entry
      </label>
      <small class="prayer-note">
        {#if !savePrayer}
          Your prayer will go to God but won't be saved in your journal
        {:else}
          Your prayer will be saved to look back on later
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
      Share with Community
    </label>
    
    {#if shareToFeed}
      <div class="sharing-options">
        <div class="share-type">
          <label>Share as:</label>
          <select bind:value={shareType}>
            <option value="post">Status Update</option>
            <option value="prayer">Prayer Request</option>
            <option value="testimony">Testimony</option>
            <option value="praise">Praise Report</option>
          </select>
        </div>
        
        <label class="checkbox-label">
          <input 
            type="checkbox" 
            bind:checked={shareAnonymously}
          />
          Share anonymously
        </label>
        
        <small class="share-note">
          Your entry will appear in the community feed where others can pray for you and offer encouragement
        </small>
      </div>
    {/if}
  </div>
  
  <button class="submit-btn" on:click={handleSubmit}>
    {shareToFeed ? '📤 Save & Share' : '💾 Save Entry'} (2 min goal!)
  </button>
</div>

<style>
  .journal-form {
    max-width: 600px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .form-section {
    margin-bottom: 1.5rem;
  }
  
  label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: 600;
    color: #333;
  }
  
  .mood-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0.5rem;
  }
  
  .mood-btn {
    padding: 0.5rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    background: white;
    cursor: pointer;
    transition: all 0.2s;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.25rem;
  }
  
  .mood-btn:hover {
    border-color: #4a90e2;
    transform: translateY(-2px);
  }
  
  .mood-btn.selected {
    border-color: #4a90e2;
    background: #e3f2fd;
  }
  
  .emoji {
    font-size: 1.5rem;
  }
  
  .label {
    font-size: 0.75rem;
    text-transform: capitalize;
  }
  
  input, textarea {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 1rem;
    margin-bottom: 0.5rem;
  }
  
  textarea {
    resize: vertical;
    font-family: inherit;
  }
  
  .submit-btn {
    width: 100%;
    padding: 1rem;
    background: #4a90e2;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.2s;
  }
  
  .submit-btn:hover {
    background: #357abd;
  }
  
  .prayer-option {
    margin-top: 0.5rem;
  }
  
  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    font-size: 0.95rem;
  }
  
  .checkbox-label input[type="checkbox"] {
    cursor: pointer;
  }
  
  .prayer-note {
    display: block;
    margin-top: 0.25rem;
    margin-left: 1.5rem;
    color: #666;
    font-style: italic;
    font-size: 0.85rem;
  }
  
  .sharing-section {
    background: #f8f9ff;
    padding: 1rem;
    border-radius: 8px;
    border: 2px solid #e8eaf6;
  }
  
  .section-title {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 600;
    color: #667eea;
    cursor: pointer;
  }
  
  .section-title input[type="checkbox"] {
    cursor: pointer;
  }
  
  .sharing-options {
    margin-top: 1rem;
    padding-left: 1.5rem;
  }
  
  .share-type {
    margin-bottom: 1rem;
  }
  
  .share-type label {
    margin-right: 0.5rem;
  }
  
  .share-type select {
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    border: 1px solid #ddd;
  }
  
  .share-note {
    display: block;
    margin-top: 0.5rem;
    color: #666;
    font-size: 0.85rem;
    line-height: 1.4;
  }
</style>