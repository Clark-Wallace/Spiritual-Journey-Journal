<script lang="ts">
  import { journalEntries } from '../stores';
  
  let expandedDates: Set<string> = new Set();
  let expandedEntries: Set<string> = new Set();
  
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
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      year: 'numeric'
    });
  }
  
  function formatShortDate(date: Date | string) {
    return new Date(date).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  }
  
  // Group entries by date
  $: entriesByDate = $journalEntries.reduce((groups, entry) => {
    const dateKey = formatShortDate(entry.date);
    if (!groups[dateKey]) {
      groups[dateKey] = [];
    }
    groups[dateKey].push(entry);
    return groups;
  }, {} as Record<string, typeof $journalEntries>);
  
  $: sortedDates = Object.keys(entriesByDate).sort((a, b) => 
    new Date(b).getTime() - new Date(a).getTime()
  );
  
  function toggleDate(date: string) {
    if (expandedDates.has(date)) {
      expandedDates.delete(date);
    } else {
      expandedDates.add(date);
    }
    expandedDates = expandedDates;
  }
  
  function toggleEntry(id: string) {
    if (expandedEntries.has(id)) {
      expandedEntries.delete(id);
    } else {
      expandedEntries.add(id);
    }
    expandedEntries = expandedEntries;
  }
</script>

<div class="journal-list-collapsible">
  <div class="list-header">
    <h3>📔 Recent Journal Entries</h3>
    <p class="entries-count">{$journalEntries.length} total entries</p>
  </div>
  
  {#if $journalEntries.length === 0}
    <div class="empty-state">
      <p>No journal entries yet. Start documenting your journey!</p>
    </div>
  {:else}
    <div class="entries-timeline">
      {#each sortedDates as dateKey}
        <div class="date-group">
          <button 
            class="date-header"
            class:expanded={expandedDates.has(dateKey)}
            on:click={() => toggleDate(dateKey)}
          >
            <span class="expand-icon">{expandedDates.has(dateKey) ? '▼' : '▶'}</span>
            <span class="date-text">{dateKey}</span>
            <span class="count-badge">{entriesByDate[dateKey].length}</span>
          </button>
          
          {#if expandedDates.has(dateKey)}
            <div class="date-entries">
              {#each entriesByDate[dateKey] as entry}
                <div class="entry-compact">
                  <button 
                    class="entry-header"
                    on:click={() => toggleEntry(entry.id)}
                  >
                    <div class="entry-summary">
                      {#if entry.mood}
                        <span class="mood-icon">{moodEmojis[entry.mood]}</span>
                      {/if}
                      <span class="entry-preview">
                        {entry.content ? entry.content.slice(0, 50) + '...' : 'No content'}
                      </span>
                    </div>
                    <span class="expand-hint">{expandedEntries.has(entry.id) ? '−' : '+'}</span>
                  </button>
                  
                  {#if expandedEntries.has(entry.id)}
                    <div class="entry-details">
                      {#if entry.mood}
                        <div class="detail-row">
                          <span class="detail-label">Mood:</span>
                          <span class="detail-value">{moodEmojis[entry.mood]} {entry.mood}</span>
                        </div>
                      {/if}
                      
                      {#if entry.gratitude && entry.gratitude.length > 0}
                        <div class="detail-row">
                          <span class="detail-label">Grateful for:</span>
                          <div class="gratitude-list">
                            {#each entry.gratitude as item}
                              <span class="gratitude-item">• {item}</span>
                            {/each}
                          </div>
                        </div>
                      {/if}
                      
                      {#if entry.content}
                        <div class="detail-row">
                          <span class="detail-label">Reflection:</span>
                          <p class="content-text">{entry.content}</p>
                        </div>
                      {/if}
                      
                      {#if entry.prayer}
                        <div class="detail-row prayer-row">
                          <span class="detail-label">🙏 Prayer:</span>
                          <p class="prayer-text">{entry.prayer}</p>
                        </div>
                      {/if}
                      
                      <button 
                        class="delete-btn" 
                        on:click|stopPropagation={() => journalEntries.deleteEntry(entry.id)}
                      >
                        🗑️ Delete
                      </button>
                    </div>
                  {/if}
                </div>
              {/each}
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .journal-list-collapsible {
    max-width: 700px;
    margin: 0 auto;
  }
  
  .list-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1.5rem;
    padding: 1rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.08), rgba(255, 193, 7, 0.04));
    border: 1px solid var(--border-gold);
    border-radius: 10px;
  }
  
  .list-header h3 {
    color: var(--text-divine);
    margin: 0;
    font-size: 1.2rem;
  }
  
  .entries-count {
    color: var(--text-scripture);
    margin: 0;
    font-size: 0.9rem;
  }
  
  .empty-state {
    text-align: center;
    padding: 2rem;
    color: var(--text-scripture);
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border-gold);
    border-radius: 10px;
  }
  
  .entries-timeline {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  
  .date-group {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    overflow: hidden;
  }
  
  .date-header {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 1rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.05), rgba(255, 193, 7, 0.02));
    border: none;
    color: var(--text-divine);
    cursor: pointer;
    transition: all 0.3s;
    font-size: 0.95rem;
  }
  
  .date-header:hover {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
  }
  
  .date-header.expanded {
    border-bottom: 1px solid rgba(255, 215, 0, 0.2);
  }
  
  .expand-icon {
    font-size: 0.75rem;
    transition: transform 0.3s;
  }
  
  .date-text {
    flex: 1;
    text-align: left;
    font-weight: 600;
  }
  
  .count-badge {
    background: rgba(255, 215, 0, 0.2);
    padding: 0.2rem 0.5rem;
    border-radius: 12px;
    font-size: 0.85rem;
  }
  
  .date-entries {
    padding: 0.5rem;
  }
  
  .entry-compact {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 6px;
    margin-bottom: 0.5rem;
    overflow: hidden;
  }
  
  .entry-header {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.75rem;
    background: none;
    border: none;
    color: var(--text-light);
    cursor: pointer;
    transition: all 0.3s;
    text-align: left;
  }
  
  .entry-header:hover {
    background: rgba(255, 215, 0, 0.05);
  }
  
  .entry-summary {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex: 1;
  }
  
  .mood-icon {
    font-size: 1.2rem;
  }
  
  .entry-preview {
    color: var(--text-holy);
    font-size: 0.9rem;
  }
  
  .expand-hint {
    background: rgba(255, 215, 0, 0.1);
    width: 24px;
    height: 24px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    color: var(--text-divine);
  }
  
  .entry-details {
    padding: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
    animation: slideDown 0.3s ease-out;
  }
  
  @keyframes slideDown {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
  
  .detail-row {
    margin-bottom: 0.75rem;
  }
  
  .detail-label {
    display: block;
    color: var(--text-divine);
    font-size: 0.85rem;
    font-weight: 600;
    margin-bottom: 0.25rem;
  }
  
  .detail-value {
    color: var(--text-holy);
  }
  
  .gratitude-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    margin-top: 0.25rem;
  }
  
  .gratitude-item {
    color: var(--text-holy);
    font-size: 0.9rem;
    padding-left: 0.5rem;
  }
  
  .content-text, .prayer-text {
    color: var(--text-light);
    line-height: 1.5;
    margin: 0.25rem 0 0 0;
    font-size: 0.95rem;
  }
  
  .prayer-row {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.03));
    padding: 0.75rem;
    border-radius: 6px;
    margin-top: 0.5rem;
  }
  
  .prayer-text {
    font-style: italic;
  }
  
  .delete-btn {
    margin-top: 0.75rem;
    padding: 0.4rem 0.8rem;
    background: rgba(255, 67, 54, 0.1);
    border: 1px solid rgba(255, 67, 54, 0.3);
    color: #ff4336;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.85rem;
    transition: all 0.3s;
  }
  
  .delete-btn:hover {
    background: rgba(255, 67, 54, 0.2);
    transform: scale(1.05);
  }
  
  @media (max-width: 600px) {
    .entry-preview {
      font-size: 0.85rem;
    }
  }
</style>