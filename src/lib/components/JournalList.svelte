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

<div class="journal-list">
  <h2>My Journal Entries</h2>
  
  {#each $journalEntries as entry}
    <div class="entry-card">
      <div class="entry-header">
        <span class="date">{formatDate(entry.date)}</span>
        {#if entry.mood}
          <span class="mood">
            {moodEmojis[entry.mood]} {entry.mood}
          </span>
        {/if}
      </div>
      
      {#if entry.gratitude.length > 0}
        <div class="gratitude">
          <strong>Grateful for:</strong>
          <ul>
            {#each entry.gratitude as item}
              <li>{item}</li>
            {/each}
          </ul>
        </div>
      {/if}
      
      {#if entry.content}
        <div class="content">
          <p>{entry.content}</p>
        </div>
      {/if}
      
      {#if entry.prayer}
        <div class="prayer">
          <strong>Prayer:</strong>
          <p>{entry.prayer}</p>
        </div>
      {/if}
      
      <button 
        class="delete-btn" 
        on:click={() => journalEntries.deleteEntry(entry.id)}
      >
        Delete
      </button>
    </div>
  {/each}
  
  {#if $journalEntries.length === 0}
    <p class="empty-state">No entries yet. Start your spiritual journey!</p>
  {/if}
</div>

<style>
  .journal-list {
    max-width: 600px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .entry-card {
    background: white;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  
  .entry-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.75rem;
    padding-bottom: 0.5rem;
    border-bottom: 1px solid #f0f0f0;
  }
  
  .date {
    font-weight: 600;
    color: #666;
  }
  
  .mood {
    background: #f0f0f0;
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    font-size: 0.875rem;
    text-transform: capitalize;
  }
  
  .gratitude {
    margin: 0.75rem 0;
  }
  
  .gratitude ul {
    margin: 0.25rem 0 0 1.5rem;
    padding: 0;
  }
  
  .gratitude li {
    color: #27ae60;
    margin: 0.25rem 0;
  }
  
  .content, .prayer {
    margin: 0.75rem 0;
  }
  
  .content p, .prayer p {
    margin: 0.25rem 0;
    color: #555;
    line-height: 1.5;
  }
  
  .prayer {
    background: #f9f9f9;
    padding: 0.5rem;
    border-radius: 4px;
  }
  
  .delete-btn {
    padding: 0.25rem 0.75rem;
    border: 1px solid #e74c3c;
    color: #e74c3c;
    background: white;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.875rem;
  }
  
  .delete-btn:hover {
    background: #fee;
  }
  
  .empty-state {
    text-align: center;
    color: #999;
    padding: 2rem;
  }
</style>