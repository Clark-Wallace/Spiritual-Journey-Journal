<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  type FellowshipView = 'feed' | 'members' | 'requests' | 'profile';
  
  let currentView: FellowshipView = 'feed';
  let fellowships: Set<string> = new Set();
  let fellowshipMembers: any[] = [];
  let fellowshipPosts: any[] = [];
  let fellowshipRequests: any[] = [];
  let selectedProfile: any = null;
  let loading = true;
  let newPostContent = '';
  let newPostType: 'general' | 'prayer' | 'testimony' | 'praise' = 'general';
  
  onMount(async () => {
    await loadFellowships();
    await loadFellowshipFeed();
    await loadFellowshipMembers();
  });
  
  async function loadFellowships() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('fellowships')
      .select('fellow_id')
      .eq('user_id', user.id);
    
    if (!error && data) {
      fellowships = new Set(data.map(f => f.fellow_id));
    }
  }
  
  async function loadFellowshipMembers() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('fellowships')
      .select('fellow_id, created_at')
      .eq('user_id', user.id);
    
    if (!error && data) {
      // Get member details from recent activity
      const memberIds = data.map(f => f.fellow_id);
      
      if (memberIds.length > 0) {
        const { data: memberData } = await supabase
          .from('community_posts')
          .select('user_id, user_name')
          .in('user_id', memberIds)
          .limit(100);
        
        const memberMap = new Map();
        memberData?.forEach(post => {
          if (!memberMap.has(post.user_id)) {
            memberMap.set(post.user_id, {
              id: post.user_id,
              name: post.user_name,
              joined: data.find(f => f.fellow_id === post.user_id)?.created_at
            });
          }
        });
        
        fellowshipMembers = Array.from(memberMap.values());
      }
    }
    
    loading = false;
  }
  
  async function loadFellowshipFeed() {
    const user = await getCurrentUser();
    if (!user) return;
    
    if (fellowships.size === 0) {
      await loadFellowships();
    }
    
    const fellowIds = Array.from(fellowships);
    fellowIds.push(user.id); // Include own posts
    
    if (fellowIds.length > 0) {
      const { data, error } = await supabase
        .from('community_posts')
        .select(`
          *,
          reactions (
            id,
            reaction,
            user_id
          ),
          encouragements (
            id,
            message,
            user_name,
            created_at
          )
        `)
        .in('user_id', fellowIds)
        .order('created_at', { ascending: false })
        .limit(50);
      
      if (!error) {
        fellowshipPosts = data || [];
      }
    }
  }
  
  async function createPost() {
    if (!newPostContent.trim()) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('community_posts')
      .insert({
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        content: newPostContent,
        share_type: newPostType,
        is_anonymous: false
      });
    
    if (!error) {
      newPostContent = '';
      await loadFellowshipFeed();
    }
  }
  
  async function viewProfile(userId: string) {
    const { data } = await supabase
      .from('community_posts')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(20);
    
    const { data: userData } = await supabase
      .from('journal_entries')
      .select('created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1);
    
    selectedProfile = {
      userId,
      posts: data || [],
      lastActive: userData?.[0]?.created_at,
      name: data?.[0]?.user_name || 'Unknown'
    };
    
    currentView = 'profile';
  }
  
  async function removeFellowship(fellowId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    if (confirm('Remove this person from your fellowship?')) {
      const { error } = await supabase
        .from('fellowships')
        .delete()
        .eq('user_id', user.id)
        .eq('fellow_id', fellowId);
      
      if (!error) {
        fellowships.delete(fellowId);
        fellowships = new Set(fellowships);
        await loadFellowshipMembers();
        await loadFellowshipFeed();
      }
    }
  }
  
  function formatDate(dateString: string) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    if (days < 30) return `${Math.floor(days / 7)} weeks ago`;
    return date.toLocaleDateString();
  }
</script>

<div class="fellowship-container">
  <div class="fellowship-header">
    <h1>✨ The Fellowship ✨</h1>
    <p class="subtitle">Your spiritual family and faith journey companions</p>
  </div>
  
  <div class="fellowship-nav">
    <button 
      class:active={currentView === 'feed'}
      on:click={() => currentView = 'feed'}
    >
      📜 Fellowship Feed
    </button>
    <button 
      class:active={currentView === 'members'}
      on:click={() => currentView = 'members'}
    >
      👥 My Fellowship ({fellowshipMembers.length})
    </button>
    <button 
      class:active={currentView === 'requests'}
      on:click={() => currentView = 'requests'}
    >
      ✉️ Requests {#if fellowshipRequests.length > 0}({fellowshipRequests.length}){/if}
    </button>
  </div>
  
  <div class="fellowship-content">
    {#if currentView === 'feed'}
      <!-- Post Creator -->
      <div class="post-creator">
        <h3>Share with your Fellowship</h3>
        <textarea
          bind:value={newPostContent}
          placeholder="Share what God is doing in your life..."
          rows="3"
        ></textarea>
        <div class="post-controls">
          <select bind:value={newPostType}>
            <option value="general">General</option>
            <option value="prayer">Prayer Request</option>
            <option value="testimony">Testimony</option>
            <option value="praise">Praise Report</option>
          </select>
          <button class="post-btn" on:click={createPost}>
            Share with Fellowship
          </button>
        </div>
      </div>
      
      <!-- Fellowship Feed -->
      {#if loading}
        <div class="loading">Loading fellowship updates...</div>
      {:else if fellowshipPosts.length === 0}
        <div class="empty-state">
          <h3>No Fellowship Posts Yet</h3>
          <p>Your fellowship feed will show posts from people in your fellowship.</p>
          <p>Add people to your fellowship from The Way chat to see their updates here!</p>
        </div>
      {:else}
        <div class="fellowship-feed">
          {#each fellowshipPosts as post}
            <div class="fellowship-post">
              <div class="post-header">
                <button 
                  class="author-link"
                  on:click={() => viewProfile(post.user_id)}
                >
                  <span class="author-avatar">
                    {post.user_name?.slice(0, 2).toUpperCase()}
                  </span>
                  <span class="author-name">{post.user_name}</span>
                </button>
                <span class="post-time">{formatDate(post.created_at)}</span>
              </div>
              
              {#if post.share_type !== 'general'}
                <div class="post-type post-type-{post.share_type}">
                  {#if post.share_type === 'prayer'}
                    🙏 Prayer Request
                  {:else if post.share_type === 'testimony'}
                    ✨ Testimony
                  {:else if post.share_type === 'praise'}
                    🎉 Praise Report
                  {/if}
                </div>
              {/if}
              
              <div class="post-content">
                {post.content}
              </div>
              
              <div class="post-actions">
                <button class="action-btn">
                  🙏 Pray ({post.reactions?.filter(r => r.reaction === 'pray').length || 0})
                </button>
                <button class="action-btn">
                  ❤️ Love ({post.reactions?.filter(r => r.reaction === 'love').length || 0})
                </button>
                <button class="action-btn">
                  🙌 Amen ({post.reactions?.filter(r => r.reaction === 'amen').length || 0})
                </button>
                <button class="action-btn">
                  💬 Encourage ({post.encouragements?.length || 0})
                </button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
      
    {:else if currentView === 'members'}
      <!-- Fellowship Members List -->
      <div class="members-list">
        <h3>Your Fellowship Members</h3>
        {#if fellowshipMembers.length === 0}
          <div class="empty-state">
            <p>No one in your fellowship yet.</p>
            <p>Add believers from The Way chat to build your fellowship!</p>
          </div>
        {:else}
          {#each fellowshipMembers as member}
            <div class="member-card">
              <div class="member-avatar">
                {member.name?.slice(0, 2).toUpperCase()}
              </div>
              <div class="member-info">
                <button 
                  class="member-name"
                  on:click={() => viewProfile(member.id)}
                >
                  {member.name}
                </button>
                <div class="member-meta">
                  Fellowship since {formatDate(member.joined)}
                </div>
              </div>
              <button 
                class="remove-btn"
                on:click={() => removeFellowship(member.id)}
                title="Remove from fellowship"
              >
                ✕
              </button>
            </div>
          {/each}
        {/if}
      </div>
      
    {:else if currentView === 'requests'}
      <!-- Fellowship Requests -->
      <div class="requests-section">
        <h3>Fellowship Requests</h3>
        {#if fellowshipRequests.length === 0}
          <div class="empty-state">
            <p>No pending fellowship requests.</p>
            <p>Fellowship connections are mutual - both people need to add each other.</p>
          </div>
        {:else}
          {#each fellowshipRequests as request}
            <div class="request-card">
              <div class="request-info">
                <span class="requester-name">{request.name}</span>
                <span class="request-time">{formatDate(request.created_at)}</span>
              </div>
              <div class="request-actions">
                <button class="accept-btn">✓ Accept</button>
                <button class="decline-btn">✕ Decline</button>
              </div>
            </div>
          {/each}
        {/if}
      </div>
      
    {:else if currentView === 'profile' && selectedProfile}
      <!-- Profile View -->
      <div class="profile-view">
        <button class="back-btn" on:click={() => currentView = 'feed'}>
          ← Back to Feed
        </button>
        
        <div class="profile-header">
          <div class="profile-avatar">
            {selectedProfile.name?.slice(0, 2).toUpperCase()}
          </div>
          <div class="profile-info">
            <h2>{selectedProfile.name}</h2>
            {#if selectedProfile.lastActive}
              <p>Last active: {formatDate(selectedProfile.lastActive)}</p>
            {/if}
          </div>
        </div>
        
        <div class="profile-posts">
          <h3>Recent Posts</h3>
          {#each selectedProfile.posts as post}
            <div class="profile-post">
              <div class="post-date">{formatDate(post.created_at)}</div>
              <div class="post-content">{post.content}</div>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .fellowship-container {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .fellowship-header {
    text-align: center;
    margin-bottom: 2rem;
    padding: 2rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(30, 144, 255, 0.1));
    border-radius: 15px;
    border: 1px solid var(--border-gold);
  }
  
  .fellowship-header h1 {
    color: var(--text-divine);
    margin: 0;
    font-size: 2.5rem;
  }
  
  .subtitle {
    color: var(--text-scripture);
    margin: 0.5rem 0 0 0;
    font-style: italic;
  }
  
  .fellowship-nav {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 2rem;
    border-bottom: 1px solid var(--border-gold);
    padding-bottom: 1rem;
  }
  
  .fellowship-nav button {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid transparent;
    color: var(--text-light);
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .fellowship-nav button:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
  }
  
  .fellowship-nav button.active {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    font-weight: 600;
  }
  
  .post-creator {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 2rem;
  }
  
  .post-creator h3 {
    color: var(--text-divine);
    margin: 0 0 1rem 0;
  }
  
  .post-creator textarea {
    width: 100%;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    padding: 0.75rem;
    border-radius: 8px;
    font-family: inherit;
    resize: vertical;
  }
  
  .post-controls {
    display: flex;
    gap: 1rem;
    margin-top: 1rem;
    align-items: center;
  }
  
  .post-controls select {
    padding: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    border-radius: 6px;
  }
  
  .post-btn {
    padding: 0.5rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 20px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .post-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.3);
  }
  
  .fellowship-feed {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  
  .fellowship-post {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 12px;
    padding: 1.5rem;
    transition: all 0.3s;
  }
  
  .fellowship-post:hover {
    background: rgba(255, 255, 255, 0.05);
    border-color: var(--border-gold);
  }
  
  .post-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }
  
  .author-link {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: none;
    color: var(--text-light);
    cursor: pointer;
    padding: 0;
    transition: all 0.2s;
  }
  
  .author-link:hover {
    color: var(--text-divine);
  }
  
  .author-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 0.9rem;
  }
  
  .author-name {
    font-weight: 600;
    color: var(--text-divine);
  }
  
  .post-time {
    color: var(--text-scripture);
    font-size: 0.85rem;
  }
  
  .post-type {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 15px;
    font-size: 0.85rem;
    margin-bottom: 0.75rem;
    font-weight: 600;
  }
  
  .post-type-prayer {
    background: rgba(138, 43, 226, 0.2);
    color: #b19cd9;
  }
  
  .post-type-testimony {
    background: rgba(255, 215, 0, 0.2);
    color: var(--text-divine);
  }
  
  .post-type-praise {
    background: rgba(76, 175, 80, 0.2);
    color: #81c784;
  }
  
  .post-content {
    color: var(--text-light);
    line-height: 1.6;
    margin-bottom: 1rem;
  }
  
  .post-actions {
    display: flex;
    gap: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .action-btn {
    padding: 0.25rem 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-scripture);
    border-radius: 15px;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.85rem;
  }
  
  .action-btn:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
    color: var(--text-divine);
  }
  
  .members-list {
    background: rgba(255, 255, 255, 0.03);
    border-radius: 12px;
    padding: 1.5rem;
  }
  
  .members-list h3 {
    color: var(--text-divine);
    margin: 0 0 1.5rem 0;
  }
  
  .member-card {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 10px;
    margin-bottom: 0.75rem;
    transition: all 0.2s;
  }
  
  .member-card:hover {
    background: rgba(255, 255, 255, 0.05);
    border-color: var(--border-gold);
  }
  
  .member-avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.3), rgba(138, 43, 226, 0.3));
    color: var(--text-divine);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
  }
  
  .member-info {
    flex: 1;
  }
  
  .member-name {
    background: none;
    border: none;
    color: var(--text-divine);
    font-weight: 600;
    font-size: 1rem;
    cursor: pointer;
    padding: 0;
    text-align: left;
  }
  
  .member-name:hover {
    text-decoration: underline;
  }
  
  .member-meta {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin-top: 0.25rem;
  }
  
  .remove-btn {
    padding: 0.25rem 0.5rem;
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
    border: 1px solid rgba(255, 87, 34, 0.3);
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .remove-btn:hover {
    background: rgba(255, 87, 34, 0.3);
    transform: scale(1.1);
  }
  
  .empty-state {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  .empty-state h3 {
    color: var(--text-divine);
    margin-bottom: 1rem;
  }
  
  .profile-view {
    background: rgba(255, 255, 255, 0.03);
    border-radius: 12px;
    padding: 1.5rem;
  }
  
  .back-btn {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    border-radius: 8px;
    cursor: pointer;
    margin-bottom: 1.5rem;
  }
  
  .back-btn:hover {
    background: rgba(255, 215, 0, 0.1);
  }
  
  .profile-header {
    display: flex;
    gap: 1.5rem;
    align-items: center;
    padding-bottom: 1.5rem;
    border-bottom: 1px solid var(--border-gold);
    margin-bottom: 2rem;
  }
  
  .profile-avatar {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.4), rgba(138, 43, 226, 0.4));
    color: var(--text-divine);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 1.5rem;
  }
  
  .profile-info h2 {
    color: var(--text-divine);
    margin: 0;
  }
  
  .profile-info p {
    color: var(--text-scripture);
    margin: 0.5rem 0 0 0;
  }
  
  .profile-posts h3 {
    color: var(--text-divine);
    margin-bottom: 1rem;
  }
  
  .profile-post {
    padding: 1rem;
    background: rgba(0, 0, 0, 0.2);
    border-left: 3px solid var(--border-gold);
    margin-bottom: 1rem;
  }
  
  .post-date {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin-bottom: 0.5rem;
  }
  
  .loading {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  @media (max-width: 600px) {
    .fellowship-container {
      padding: 0.5rem;
    }
    
    .fellowship-nav {
      flex-wrap: wrap;
    }
    
    .fellowship-nav button {
      font-size: 0.85rem;
      padding: 0.4rem 0.8rem;
    }
    
    .post-actions {
      flex-wrap: wrap;
      gap: 0.5rem;
    }
  }
</style>