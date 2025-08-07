<script lang="ts">
  import { prayers } from '../stores';
  import type { Prayer } from '../types';
  
  let showForm = false;
  let content = '';
  let category: Prayer['category'] = 'petition';
  
  const categories: Prayer['category'][] = [
    'thanksgiving', 'intercession', 'petition', 
    'confession', 'praise', 'guidance'
  ];
  
  async function addPrayer() {
    if (!content) {
      alert('Please enter your prayer');
      return;
    }
    
    try {
      await prayers.addPrayer({
        request: content,
        category,
        status: 'active'
      });
      
      content = '';
      category = 'petition';
      showForm = false;
    } catch (error) {
      console.error('Error adding prayer:', error);
      alert('Failed to add prayer. Please try again.');
    }
  }
  
  async function markAnswered(prayer: Prayer) {
    const note = prompt('How did God answer this prayer?');
    if (note) {
      try {
        await prayers.answerPrayer(prayer.id, note);
      } catch (error) {
        console.error('Error marking prayer as answered:', error);
        alert('Failed to update prayer. Please try again.');
      }
    }
  }
</script>

<div class="prayer-container">
  <div class="header">
    <h2>My Prayers</h2>
    <button class="add-btn" on:click={() => showForm = !showForm}>
      {showForm ? '✕' : '+'} {showForm ? 'Cancel' : 'Add Prayer'}
    </button>
  </div>
  
  {#if showForm}
    <div class="prayer-form">
      <textarea
        placeholder="Enter your prayer request..."
        bind:value={content}
        rows="5"
      ></textarea>
      
      <div class="category-select">
        <label>Category:</label>
        <select bind:value={category}>
          {#each categories as cat}
            <option value={cat}>{cat}</option>
          {/each}
        </select>
      </div>
      
      <button class="save-btn" on:click={addPrayer}>Save Prayer</button>
    </div>
  {/if}
  
  <div class="prayers-list">
    {#each $prayers as prayer}
      <div class="prayer-card" class:answered={prayer.status === 'answered'}>
        <div class="prayer-header">
          <span class="badge {prayer.category}">{prayer.category}</span>
          {#if prayer.status === 'answered'}
            <span class="badge answered">✓ Answered</span>
          {/if}
        </div>
        
        <p class="prayer-content">{prayer.request}</p>
        
        {#if prayer.answeredNote}
          <div class="answer-note">
            <strong>God's Answer:</strong> {prayer.answeredNote}
          </div>
        {/if}
        
        <div class="prayer-actions">
          {#if prayer.status === 'active'}
            <button on:click={() => markAnswered(prayer)}>Mark Answered</button>
          {/if}
          <button class="delete-btn" on:click={() => prayers.deletePrayer(prayer.id)}>Delete</button>
        </div>
      </div>
    {/each}
    
    {#if $prayers.length === 0}
      <p class="empty-state">No prayers yet. Add your first prayer above!</p>
    {/if}
  </div>
</div>

<style>
  .prayer-container {
    max-width: 600px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }
  
  .add-btn {
    padding: 0.5rem 1rem;
    background: #4a90e2;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
  }
  
  .prayer-form {
    background: #f5f5f5;
    padding: 1rem;
    border-radius: 8px;
    margin-bottom: 1rem;
  }
  
  .prayer-form input,
  .prayer-form textarea,
  .prayer-form select {
    width: 100%;
    padding: 0.5rem;
    margin-bottom: 0.5rem;
    border: 1px solid #ddd;
    border-radius: 4px;
  }
  
  .category-select {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }
  
  .category-select select {
    flex: 1;
  }
  
  .save-btn {
    width: 100%;
    padding: 0.75rem;
    background: #27ae60;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-weight: 600;
  }
  
  .prayer-card {
    background: white;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  
  .prayer-card.answered {
    background: #f0f9ff;
    border-color: #27ae60;
  }
  
  .prayer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
  }
  
  .prayer-header h3 {
    margin: 0;
    font-size: 1.1rem;
  }
  
  .badge {
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    font-size: 0.75rem;
    text-transform: uppercase;
    font-weight: 600;
  }
  
  .badge.answered {
    background: #27ae60;
    color: white;
  }
  
  .badge.petition { background: #e3f2fd; color: #1976d2; }
  .badge.thanksgiving { background: #fff3e0; color: #f57c00; }
  .badge.praise { background: #fce4ec; color: #c2185b; }
  .badge.intercession { background: #f3e5f5; color: #7b1fa2; }
  .badge.confession { background: #e8eaf6; color: #3f51b5; }
  .badge.guidance { background: #e0f2f1; color: #00695c; }
  
  .prayer-content {
    color: #555;
    margin: 0.5rem 0;
  }
  
  .answer-note {
    background: #e8f5e9;
    padding: 0.5rem;
    border-radius: 4px;
    margin: 0.5rem 0;
    font-size: 0.9rem;
  }
  
  .prayer-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }
  
  .prayer-actions button {
    padding: 0.25rem 0.75rem;
    border: 1px solid #ddd;
    background: white;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.875rem;
  }
  
  .prayer-actions button:hover {
    background: #f5f5f5;
  }
  
  .delete-btn {
    color: #e74c3c;
  }
  
  .empty-state {
    text-align: center;
    color: #999;
    padding: 2rem;
  }
</style>