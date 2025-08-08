<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  export let show = false;
  
  let fellowships: any[] = [];
  let incomingRequests: any[] = [];
  let loading = false;
  let searchTerm = '';
  let searchResults: any[] = [];
  let searching = false;
  let activeTab: 'requests' | 'fellowship' = 'requests';
  let requestSubscription: any;
  
  onMount(() => {
    if (show) {
      loadFellowships();
      loadRequests();
      setupRequestSubscription();
    }
    
    return () => {
      if (requestSubscription) {
        supabase.removeChannel(requestSubscription);
      }
    };
  });
  
  $: if (show) {
    loadFellowships();
    loadRequests();
    setupRequestSubscription();
    // Default to requests tab if there are any
    if (incomingRequests.length > 0) {
      activeTab = 'requests';
    }
  }
  
  async function setupRequestSubscription() {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Clean up existing subscription
    if (requestSubscription) {
      supabase.removeChannel(requestSubscription);
    }
    
    // Subscribe to changes in fellowship_requests
    requestSubscription = supabase
      .channel('fellowship-requests')
      .on('postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'fellowship_requests',
          filter: `to_user_id=eq.${user.id}`
        },
        (payload) => {
          console.log('Fellowship request change:', payload);
          loadRequests();
        }
      )
      .subscribe();
  }
  
  async function loadFellowships() {
    loading = true;
    const user = await authStore.getUser();
    if (!user) return;
    
    // Try the RPC function which now uses user_profiles
    const { data, error } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowships:', error);
      // Fallback to direct query with user_profiles join
      const { data: fallbackData, error: fallbackError } = await supabase
        .from('fellowships')
        .select(`
          fellow_id,
          created_at,
          user_profiles!fellow_id (
            display_name
          )
        `)
        .eq('user_id', user.id);
      
      if (!fallbackError && fallbackData) {
        fellowships = fallbackData.map(f => ({
          fellow_id: f.fellow_id,
          fellow_name: f.user_profiles?.display_name || 'Unknown',
          created_at: f.created_at
        }));
      }
    } else {
      fellowships = data || [];
    }
    
    loading = false;
  }
  
  async function loadRequests() {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('get_fellowship_requests', { p_user_id: user.id });
    
    if (error) {
      console.error('Error loading requests via RPC:', error);
      // Fallback: try direct query
      const { data: fallbackData, error: fallbackError } = await supabase
        .from('fellowship_requests')
        .select(`
          *,
          from_profile:user_profiles!fellowship_requests_from_user_id_fkey(display_name),
          to_profile:user_profiles!fellowship_requests_to_user_id_fkey(display_name)
        `)
        .eq('to_user_id', user.id)
        .eq('status', 'pending')
        .neq('from_user_id', user.id); // Don't show self-requests
      
      if (!fallbackError && fallbackData) {
        console.log('Loaded requests via fallback:', fallbackData);
        incomingRequests = fallbackData.map(req => ({
          request_id: req.id,
          from_user_id: req.from_user_id,
          from_user_name: req.from_profile?.display_name || 'Unknown',
          to_user_id: req.to_user_id,
          to_user_name: req.to_profile?.display_name || 'Unknown',
          status: req.status,
          created_at: req.created_at,
          direction: 'received'
        }));
      }
    } else if (data) {
      console.log('Loaded requests via RPC:', data);
      console.log('Filtering for received requests...');
      incomingRequests = data.filter((req: any) => req.direction === 'received');
      console.log('Incoming requests after filter:', incomingRequests);
    }
  }
  
  async function acceptRequest(requestId: string, fromUserId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('accept_fellowship_request', {
        p_request_id: requestId,
        p_user_id: user.id
      });
    
    if (error) {
      console.error('Error accepting request:', error);
      alert('Failed to accept fellowship request. Please try again.');
      return;
    }
    
    if (data?.success) {
      console.log('Fellowship request accepted successfully');
    }
    
    // Reload data
    await loadRequests();
    await loadFellowships();
  }
  
  async function declineRequest(requestId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('decline_fellowship_request', {
        p_request_id: requestId,
        p_user_id: user.id
      });
    
    if (error) {
      console.error('Error declining request:', error);
      alert('Failed to decline fellowship request. Please try again.');
      return;
    }
    
    if (data?.success) {
      console.log('Fellowship request declined');
    }
    
    await loadRequests();
  }
  
  async function searchUsers() {
    if (!searchTerm.trim()) {
      searchResults = [];
      return;
    }
    
    searching = true;
    const user = await authStore.getUser();
    
    // First try the RPC function
    const { data: rpcData, error: rpcError } = await supabase
      .rpc('get_all_users_with_profiles');
    
    if (!rpcError && rpcData) {
      // Filter results based on search term and existing fellowships
      searchResults = (rpcData || [])
        .filter(u => u.user_id !== user?.id)
        .filter(u => !fellowships.find(f => f.fellow_id === u.user_id))
        .filter(u => u.display_name.toLowerCase().includes(searchTerm.toLowerCase()))
        .slice(0, 10)
        .map(u => ({
          user_id: u.user_id,
          user_name: u.display_name
        }));
    } else {
      // Fallback to searching in user_profiles table directly
      let { data: profileData } = await supabase
        .from('user_profiles')
        .select('user_id, display_name')
        .neq('user_id', user?.id)
        .limit(20);
      
      if (profileData) {
        // Filter locally
        searchResults = profileData
          .filter(profile => !fellowships.find(f => f.fellow_id === profile.user_id))
          .filter(profile => profile.display_name.toLowerCase().includes(searchTerm.toLowerCase()))
          .slice(0, 10)
          .map(profile => ({
            user_id: profile.user_id,
            user_name: profile.display_name
          }));
      } else {
        // Last resort: search in community posts
        const { data: postsData } = await supabase
          .from('community_posts')
          .select('user_id, user_name')
          .neq('user_id', user?.id)
          .limit(50);
        
        if (postsData) {
          // Get unique users
          const uniqueUsers = new Map();
          postsData.forEach(post => {
            if (!uniqueUsers.has(post.user_id) && 
                !fellowships.find(f => f.fellow_id === post.user_id) &&
                post.user_name.toLowerCase().includes(searchTerm.toLowerCase())) {
              uniqueUsers.set(post.user_id, post.user_name);
            }
          });
          
          searchResults = Array.from(uniqueUsers, ([user_id, user_name]) => ({
            user_id,
            user_name
          })).slice(0, 10);
        }
      }
    }
    
    searching = false;
  }
  
  async function addToFellowship(fellowId: string, fellowName: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    console.log('Sending fellowship request from', user.id, 'to', fellowId);
    
    // Note: We can't save other users' profiles due to RLS policies
    // Their profile should already exist from when they signed up
    
    // Send fellowship request
    const { data, error } = await supabase
      .rpc('send_fellowship_request', {
        p_from_user_id: user.id,
        p_to_user_id: fellowId
      });
    
    console.log('Send request response:', data, error);
    
    if (error) {
      console.error('Error sending request:', error);
      // Fallback to direct insert
      const { error: insertError } = await supabase
        .from('fellowship_requests')
        .insert({
          from_user_id: user.id,
          to_user_id: fellowId,
          status: 'pending'
        });
      
      if (!insertError) {
        console.log('Request sent via fallback');
        alert('Fellowship request sent!');
      } else {
        console.error('Fallback also failed:', insertError);
        alert('Failed to send fellowship request');
      }
    } else if (data?.success) {
      console.log('Request sent successfully:', data.message);
      if (data.message === 'Fellowship established (mutual request)') {
        // They already requested us - auto accepted
        await loadFellowships();
        alert('Fellowship established! They had already requested you.');
      } else if (data.message === 'Already in fellowship') {
        alert('You are already in fellowship with this person');
      } else if (data.message === 'Request already pending') {
        alert('Fellowship request already pending');
      } else {
        alert('Fellowship request sent!');
      }
    }
    
    // Clear search
    searchTerm = '';
    searchResults = [];
  }
  
  function formatDate(dateString: string) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);
    
    if (minutes < 1) return 'just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;
    return date.toLocaleDateString();
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
        <!-- Tab Navigation -->
        <div class="tab-nav">
          <button 
            class="tab-btn {activeTab === 'requests' ? 'active' : ''}"
            on:click={() => activeTab = 'requests'}
          >
            ✉️ Requests {#if incomingRequests.length > 0}({incomingRequests.length}){/if}
          </button>
          <button 
            class="tab-btn {activeTab === 'fellowship' ? 'active' : ''}"
            on:click={() => activeTab = 'fellowship'}
          >
            👥 Fellowship ({fellowships.length})
          </button>
        </div>
        
        {#if activeTab === 'requests'}
          <!-- Requests Tab -->
          <div class="requests-section">
            {#if incomingRequests.length === 0}
              <div class="empty">
                <p>No pending fellowship requests</p>
                <p class="hint">When someone wants to join your fellowship, it will appear here</p>
              </div>
            {:else}
              <div class="requests-list">
                {#each incomingRequests as request}
                  <div class="request-card">
                    <div class="request-info">
                      <span class="request-icon">👤</span>
                      <div class="request-details">
                        <span class="request-name">{request.from_user_name}</span>
                        <span class="request-time">Requested {formatDate(request.created_at)}</span>
                      </div>
                    </div>
                    <div class="request-actions">
                      <button 
                        class="accept-btn"
                        on:click={() => acceptRequest(request.request_id, request.from_user_id)}
                      >
                        ✓ Accept
                      </button>
                      <button 
                        class="decline-btn"
                        on:click={() => declineRequest(request.request_id)}
                      >
                        ✕ Decline
                      </button>
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </div>
        {:else}
          <!-- Fellowship Tab -->
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
                      ➕ Send Request
                    </button>
                  </div>
                {/each}
              </div>
            {/if}
          </div>
          
          <!-- Fellowship List -->
          <div class="fellowship-list">
            <h3>Fellowship Members</h3>
            
            {#if loading}
              <div class="loading">Loading fellowship...</div>
            {:else if fellowships.length === 0}
              <div class="empty">
                <p>No one in your fellowship yet.</p>
                <p class="hint">Search above to send fellowship requests!</p>
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
        {/if}
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
  
  .tab-nav {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
    border-bottom: 1px solid var(--border-gold);
    padding-bottom: 0.5rem;
  }
  
  .tab-btn {
    background: transparent;
    border: none;
    color: var(--text-scripture);
    padding: 0.5rem 1rem;
    cursor: pointer;
    font-size: 0.95rem;
    transition: all 0.2s;
    border-bottom: 2px solid transparent;
    font-family: inherit;
  }
  
  .tab-btn:hover {
    color: var(--text-divine);
  }
  
  .tab-btn.active {
    color: var(--text-divine);
    border-bottom-color: var(--primary-gold);
  }
  
  .requests-section {
    animation: fadeIn 0.3s ease-out;
  }
  
  .requests-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  
  .request-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    transition: all 0.2s;
  }
  
  .request-card:hover {
    background: rgba(255, 255, 255, 0.05);
    border-color: rgba(255, 215, 0, 0.3);
  }
  
  .request-info {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  
  .request-icon {
    font-size: 1.8rem;
  }
  
  .request-details {
    display: flex;
    flex-direction: column;
  }
  
  .request-name {
    color: var(--text-light);
    font-size: 1rem;
    font-weight: 500;
  }
  
  .request-time {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin-top: 0.25rem;
  }
  
  .request-actions {
    display: flex;
    gap: 0.5rem;
  }
  
  .accept-btn, .decline-btn {
    padding: 0.4rem 0.8rem;
    border-radius: 6px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
    font-weight: 500;
    border: none;
  }
  
  .accept-btn {
    background: rgba(76, 175, 80, 0.2);
    color: #4caf50;
    border: 1px solid rgba(76, 175, 80, 0.3);
  }
  
  .accept-btn:hover {
    background: rgba(76, 175, 80, 0.3);
    transform: scale(1.05);
  }
  
  .decline-btn {
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
    border: 1px solid rgba(255, 87, 34, 0.3);
  }
  
  .decline-btn:hover {
    background: rgba(255, 87, 34, 0.3);
    transform: scale(1.05);
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