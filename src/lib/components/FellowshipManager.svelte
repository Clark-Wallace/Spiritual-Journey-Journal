<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  export let show = false;
  
  let fellowships: any[] = [];
  let loading = false;
  let searchTerm = '';
  let searchResults: any[] = [];
  let searching = false;
  
  onMount(() => {
    if (show) {
      loadFellowships();
    }
  });
  
  $: if (show) {
    loadFellowships();
  }
  
  async function loadFellowships() {
    loading = true;
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowships:', error);
    } else {
      fellowships = data || [];
    }
    
    loading = false;
  }
  
  async function searchUsers() {
    if (!searchTerm.trim()) {
      searchResults = [];
      return;
    }
    
    searching = true;
    const user = await authStore.getUser();
    
    // Search in community posts for active users
    const { data, error } = await supabase
      .from('community_posts')
      .select('user_id, user_name')
      .ilike('user_name', `%${searchTerm}%`)
      .neq('user_id', user?.id)
      .limit(10);
    
    if (error) {
      console.error('Error searching users:', error);
    } else {
      // Remove duplicates and filter out existing fellows
      const uniqueUsers = new Map();
      data?.forEach(post => {
        if (!fellowships.find(f => f.fellow_id === post.user_id)) {
          uniqueUsers.set(post.user_id, post.user_name);
        }
      });
      
      searchResults = Array.from(uniqueUsers, ([user_id, user_name]) => ({
        user_id,
        user_name
      }));
    }
    
    searching = false;
  }
  
  async function addToFellowship(fellowId: string, fellowName: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('fellowships')
      .insert({
        user_id: user.id,
        fellow_id: fellowId
      });
    
    if (error) {
      console.error('Error adding to fellowship:', error);
      alert('Failed to add to fellowship');
    } else {
      // Add to local list immediately
      fellowships = [...fellowships, {
        fellow_id: fellowId,
        fellow_name: fellowName,
        created_at: new Date().toISOString()
      }];
      
      // Clear search
      searchTerm = '';
      searchResults = [];
    }
  }
  
  async function removeFromFellowship(fellowId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    if (!confirm('Remove this person from your fellowship?')) return;
    
    const { error } = await supabase
      .from('fellowships')
      .delete()
      .eq('user_id', user.id)
      .eq('fellow_id', fellowId);
    
    if (error) {
      console.error('Error removing from fellowship:', error);
    } else {
      fellowships = fellowships.filter(f => f.fellow_id !== fellowId);
    }
  }
  
  function close() {
    show = false;
    searchTerm = '';
    searchResults = [];
  }
</script>

{#if show}
  <div class="fellowship-overlay" on:click={close}>
    <div class="fellowship-modal" on:click|stopPropagation>
      <div class="modal-header">
        <h2>👥 Your Fellowship</h2>
        <button class="close-btn" on:click={close}>✕</button>
      </div>
      
      <div class="modal-content">
        <!-- Search Section -->
        <div class="search-section">
          <input
            type="text"
            placeholder="Search for believers to add..."
            bind:value={searchTerm}
            on:input={searchUsers}
            class="search-input"
          />
          
          {#if searching}
            <div class="searching">Searching...</div>
          {/if}
          
          {#if searchResults.length > 0}
            <div class="search-results">
              {#each searchResults as result}
                <div class="search-result">
                  <span class="user-name">{result.user_name}</span>
                  <button 
                    class="add-btn"
                    on:click={() => addToFellowship(result.user_id, result.user_name)}
                  >
                    ➕ Add
                  </button>
                </div>
              {/each}
            </div>
          {/if}
        </div>
        
        <!-- Fellowship List -->
        <div class="fellowship-list">
          <h3>Fellowship Members ({fellowships.length})</h3>
          
          {#if loading}
            <div class="loading">Loading fellowship...</div>
          {:else if fellowships.length === 0}
            <div class="empty">
              <p>No one in your fellowship yet.</p>
              <p class="hint">Search above to add fellow believers!</p>
            </div>
          {:else}
            {#each fellowships as fellow}
              <div class="fellow-card">
                <div class="fellow-info">
                  <span class="fellow-icon">👤</span>
                  <span class="fellow-name">{fellow.fellow_name}</span>
                </div>
                <button 
                  class="remove-btn"
                  on:click={() => removeFromFellowship(fellow.fellow_id)}
                  title="Remove from fellowship"
                >
                  ✕
                </button>
              </div>
            {/each}
          {/if}
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  .fellowship-overlay {
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
    z-index: 1000;
    animation: fadeIn 0.3s ease-out;
  }
  
  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }
  
  .fellowship-modal {
    background: var(--bg-dark);
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    width: 90%;
    max-width: 500px;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
    animation: slideUp 0.3s ease-out;
  }
  
  @keyframes slideUp {
    from {
      transform: translateY(20px);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }
  
  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem;
    border-bottom: 1px solid var(--border-gold);
  }
  
  .modal-header h2 {
    margin: 0;
    color: var(--text-divine);
    font-size: 1.5rem;
  }
  
  .close-btn {
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 1.5rem;
    cursor: pointer;
    padding: 0;
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.2s;
  }
  
  .close-btn:hover {
    color: var(--text-divine);
    transform: scale(1.1);
  }
  
  .modal-content {
    flex: 1;
    overflow-y: auto;
    padding: 1.5rem;
  }
  
  .search-section {
    margin-bottom: 1.5rem;
  }
  
  .search-input {
    width: 100%;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    color: var(--text-light);
    font-size: 1rem;
    font-family: inherit;
  }
  
  .search-input::placeholder {
    color: var(--text-scripture);
  }
  
  .search-input:focus {
    outline: none;
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--border-gold-strong);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .searching {
    text-align: center;
    color: var(--text-scripture);
    padding: 1rem;
    font-style: italic;
  }
  
  .search-results {
    margin-top: 0.5rem;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 0.5rem;
  }
  
  .search-result {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem;
    border-radius: 6px;
    transition: background 0.2s;
  }
  
  .search-result:hover {
    background: rgba(255, 215, 0, 0.05);
  }
  
  .user-name {
    color: var(--text-light);
  }
  
  .add-btn {
    padding: 0.25rem 0.75rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 15px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
    font-weight: 600;
  }
  
  .add-btn:hover {
    transform: scale(1.05);
    box-shadow: 0 2px 10px rgba(255, 215, 0, 0.3);
  }
  
  .fellowship-list h3 {
    color: var(--text-divine);
    margin: 0 0 1rem 0;
    font-size: 1.1rem;
  }
  
  .loading, .empty {
    text-align: center;
    padding: 2rem;
    color: var(--text-scripture);
  }
  
  .hint {
    font-size: 0.9rem;
    opacity: 0.8;
    margin-top: 0.5rem;
  }
  
  .fellow-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 8px;
    margin-bottom: 0.5rem;
    transition: all 0.2s;
  }
  
  .fellow-card:hover {
    background: rgba(255, 255, 255, 0.04);
    border-color: rgba(255, 215, 0, 0.2);
  }
  
  .fellow-info {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  
  .fellow-icon {
    font-size: 1.5rem;
  }
  
  .fellow-name {
    color: var(--text-light);
    font-size: 1rem;
  }
  
  .remove-btn {
    padding: 0.25rem 0.5rem;
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
    border: 1px solid rgba(255, 87, 34, 0.3);
    border-radius: 6px;
    font-size: 1rem;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .remove-btn:hover {
    background: rgba(255, 87, 34, 0.3);
    transform: scale(1.1);
  }
  
  @media (max-width: 600px) {
    .fellowship-modal {
      width: 95%;
      max-height: 90vh;
    }
  }
</style>