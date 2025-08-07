<script lang="ts">
  import { journalEntries } from '../stores';
  
  const moodEmojis: Record<string, string> = {
    grateful: '🙏',
    peaceful: '😌',
    joyful: '😊',
    hopeful: '✨',
    reflective: '🤔',
    troubled: '😟',
    anxious: '😰',
    seeking: '🔍'
  };
  
  function formatDate(date: Date | string) {
    return new Date(date).toLocaleDateString('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  }
</script>

<div class="journal-list-illuminated">
  <div class="list-header">
    <h2>📜 Sacred Entries</h2>
    <p class="header-subtitle">Your spiritual journey documented</p>
  </div>
  
  {#if $journalEntries.length === 0}
    <div class="empty-state">
      <div class="empty-icon">✨</div>
      <p class="empty-message">No entries yet</p>
      <p class="empty-subtitle">Begin documenting your walk with God</p>
    </div>
  {:else}
    <div class="entries-container">
      {#each $journalEntries as entry}
        <div class="entry-card">
          <div class="entry-header">
            <div class="date-badge">
              <span class="date-text">{formatDate(entry.date)}</span>
            </div>
            {#if entry.mood}
              <span class="mood-badge">
                {moodEmojis[entry.mood]} {entry.mood}
              </span>
            {/if}
          </div>
          
          {#if entry.gratitude.length > 0}
            <div class="gratitude-section">
              <div class="section-title">🙏 Grateful For:</div>
              <div class="gratitude-items">
                {#each entry.gratitude as item}
                  <span class="gratitude-tag">{item}</span>
                {/each}
              </div>
            </div>
          {/if}
          
          {#if entry.content}
            <div class="content-section">
              <p>{entry.content}</p>
            </div>
          {/if}
          
          {#if entry.prayer}
            <div class="prayer-section">
              <div class="prayer-header">
                <span class="prayer-icon">🕊️</span>
                <strong>Prayer</strong>
              </div>
              <p class="prayer-text">{entry.prayer}</p>
            </div>
          {/if}
          
          <div class="entry-actions">
            <button 
              class="delete-btn" 
              on:click={() => journalEntries.deleteEntry(entry.id)}
              title="Delete entry"
            >
              🗑️ Remove
            </button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .journal-list-illuminated {
    max-width: 700px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .list-header {
    text-align: center;
    margin-bottom: 2rem;
    padding: 1.5rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.08), rgba(255, 193, 7, 0.04));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
  }
  
  .list-header h2 {
    color: var(--text-divine);
    margin: 0 0 0.5rem 0;
    font-family: var(--font-primary);
    text-shadow: 0 0 15px rgba(255, 215, 0, 0.3);
  }
  
  .header-subtitle {
    color: var(--text-scripture);
    font-style: italic;
    font-size: 0.9rem;
    margin: 0;
  }
  
  .empty-state {
    text-align: center;
    padding: 3rem;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border-gold);
    border-radius: 12px;
  }
  
  .empty-icon {
    font-size: 3rem;
    margin-bottom: 1rem;
    filter: drop-shadow(0 0 20px rgba(255, 215, 0, 0.5));
  }
  
  .empty-message {
    color: var(--text-divine);
    font-size: 1.2rem;
    margin: 0 0 0.5rem 0;
  }
  
  .empty-subtitle {
    color: var(--text-scripture);
    font-style: italic;
    margin: 0;
  }
  
  .entries-container {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  
  .entry-card {
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.03), rgba(255, 255, 255, 0.01));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    padding: 1.5rem;
    transition: all 0.3s;
    animation: fadeIn 0.5s ease-out;
  }
  
  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
  
  .entry-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 30px rgba(255, 215, 0, 0.15);
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.05), rgba(255, 255, 255, 0.02));
  }
  
  .entry-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding-bottom: 1rem;
    border-bottom: 1px solid rgba(255, 215, 0, 0.2);
  }
  
  .date-badge {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.95rem;
    padding: 0.35rem 0.75rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    border-radius: 6px;
  }
  
  .mood-badge {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(30, 144, 255, 0.2));
    color: var(--text-holy);
    padding: 0.35rem 0.75rem;
    border-radius: 20px;
    font-size: 0.9rem;
    text-transform: capitalize;
    border: 1px solid rgba(138, 43, 226, 0.3);
  }
  
  .gratitude-section {
    margin: 1rem 0;
    padding: 1rem;
    background: rgba(255, 215, 0, 0.05);
    border-radius: 8px;
    border: 1px solid rgba(255, 215, 0, 0.2);
  }
  
  .section-title {
    color: var(--text-divine);
    font-weight: 600;
    margin-bottom: 0.75rem;
    font-size: 0.95rem;
  }
  
  .gratitude-items {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  
  .gratitude-tag {
    display: inline-block;
    padding: 0.35rem 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 15px;
    color: var(--text-holy);
    font-size: 0.9rem;
  }
  
  .content-section {
    margin: 1rem 0;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.02);
    border-left: 3px solid var(--border-gold);
    border-radius: 4px;
  }
  
  .content-section p {
    margin: 0;
    color: var(--text-light);
    line-height: 1.6;
  }
  
  .prayer-section {
    margin: 1rem 0;
    padding: 1rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.08), rgba(30, 144, 255, 0.05));
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 8px;
  }
  
  .prayer-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--text-divine);
    margin-bottom: 0.75rem;
  }
  
  .prayer-icon {
    font-size: 1.2rem;
    filter: drop-shadow(0 0 10px rgba(138, 43, 226, 0.5));
  }
  
  .prayer-text {
    margin: 0;
    color: var(--text-light);
    line-height: 1.6;
    font-style: italic;
  }
  
  .entry-actions {
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
    display: flex;
    justify-content: flex-end;
  }
  
  .delete-btn {
    padding: 0.5rem 1rem;
    border: 1px solid rgba(255, 67, 54, 0.5);
    color: #ff4336;
    background: rgba(255, 67, 54, 0.05);
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.9rem;
    transition: all 0.3s;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .delete-btn:hover {
    background: rgba(255, 67, 54, 0.1);
    border-color: #ff4336;
    transform: scale(1.05);
  }
  
  @media (max-width: 600px) {
    .entry-card {
      padding: 1rem;
    }
    
    .gratitude-items {
      flex-direction: column;
    }
    
    .gratitude-tag {
      display: block;
      text-align: center;
    }
  }
</style>