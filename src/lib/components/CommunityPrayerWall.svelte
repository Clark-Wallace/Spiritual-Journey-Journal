<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let posts: any[] = [];
  let loading = true;
  let filter: 'all' | 'prayer' | 'testimony' | 'praise' | 'gratitude' = 'all';
  let subscription: any;
  let displayMode: 'grid' | 'list' = 'grid'; // For space optimization
  
  const reactions = [
    { type: 'amen', emoji: '🙏', label: 'Amen' },
    { type: 'praying', emoji: '🤲', label: 'Praying' },
    { type: 'heart', emoji: '❤️', label: 'Love' },
    { type: 'hallelujah', emoji: '🎉', label: 'Hallelujah' },
    { type: 'strength', emoji: '💪', label: 'Strength' },
    { type: 'faith', emoji: '✨', label: 'Faith' }
  ];
  
  onMount(async () => {
    await loadPosts();
    setupRealtimeSubscriptions();
    
    return () => {
      if (subscription) {
        supabase.removeChannel(subscription);
      }
    };
  });
  
  function setupRealtimeSubscriptions() {
    subscription = supabase
      .channel('prayer_wall')
      .on('postgres_changes', 
        { event: '*', schema: 'public', table: 'community_posts' },
        (payload) => handlePostUpdate(payload)
      )
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'reactions' },
        (payload) => handleReactionUpdate(payload)
      )
      .subscribe();
  }
  
  function handlePostUpdate(payload: any) {
    const { eventType, new: newData } = payload;
    
    if (eventType === 'INSERT') {
      // Add new post to the top
      posts = [processPost(newData), ...posts];
    } else if (eventType === 'DELETE') {
      posts = posts.filter(p => p.id !== payload.old.id);
    }
  }
  
  function handleReactionUpdate(payload: any) {
    const { eventType, new: newData, old: oldData } = payload;
    const postId = newData?.post_id || oldData?.post_id;
    
    if (!postId) return;
    
    const postIndex = posts.findIndex(p => p.id === postId);
    if (postIndex === -1) return;
    
    // Reload just this post's reactions
    loadSinglePostReactions(postId, postIndex);
  }
  
  async function loadSinglePostReactions(postId: string, postIndex: number) {
    const { data } = await supabase
      .from('reactions')
      .select('*')
      .eq('post_id', postId);
    
    if (data && posts[postIndex]) {
      const user = await authStore.getUser();
      const reactionCounts: Record<string, number> = {};
      const userReactions: string[] = [];
      
      data.forEach(r => {
        reactionCounts[r.reaction_type] = (reactionCounts[r.reaction_type] || 0) + 1;
        if (r.user_id === user?.id) {
          userReactions.push(r.reaction_type);
        }
      });
      
      posts[postIndex].reaction_counts = reactionCounts;
      posts[postIndex].user_reactions = userReactions;
      posts = posts;
    }
  }
  
  function processPost(post: any) {
    const user = $authStore?.user;
    const reactionCounts: Record<string, number> = {};
    const userReactions: string[] = [];
    
    if (post.reactions) {
      post.reactions.forEach(r => {
        reactionCounts[r.reaction_type] = (reactionCounts[r.reaction_type] || 0) + 1;
        if (r.user_id === user?.id) {
          userReactions.push(r.reaction_type);
        }
      });
    }
    
    return {
      ...post,
      reaction_counts: reactionCounts,
      user_reactions: userReactions
    };
  }
  
  async function loadPosts() {
    loading = true;
    
    let query = supabase
      .from('community_posts')
      .select(`
        *,
        reactions (
          reaction_type,
          user_id
        )
      `)
      .order('created_at', { ascending: false })
      .limit(50);
    
    if (filter !== 'all') {
      if (filter === 'gratitude') {
        // Filter for posts with gratitude lists
        query = query.not('gratitude', 'is', null);
      } else {
        query = query.eq('share_type', filter);
      }
    }
    
    const { data, error } = await query;
    
    if (error) {
      console.error('Error loading posts:', error);
    } else {
      posts = (data || []).map(processPost);
    }
    
    loading = false;
  }
  
  // Remove sharePost function - entries come from journal only
  
  async function toggleReaction(postId: string, reactionType: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const postIndex = posts.findIndex(p => p.id === postId);
    if (postIndex === -1) return;
    
    const hasReaction = posts[postIndex].user_reactions?.includes(reactionType);
    
    if (hasReaction) {
      // Remove reaction
      await supabase
        .from('reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id)
        .eq('reaction_type', reactionType);
      
      // Update locally
      posts[postIndex].user_reactions = posts[postIndex].user_reactions.filter(r => r !== reactionType);
      posts[postIndex].reaction_counts[reactionType]--;
    } else {
      // Add reaction
      await supabase
        .from('reactions')
        .insert({
          post_id: postId,
          user_id: user.id,
          reaction_type: reactionType
        });
      
      // Update locally
      if (!posts[postIndex].user_reactions) {
        posts[postIndex].user_reactions = [];
      }
      posts[postIndex].user_reactions.push(reactionType);
      posts[postIndex].reaction_counts[reactionType] = (posts[postIndex].reaction_counts[reactionType] || 0) + 1;
    }
    
    posts = posts;
  }
  
  function formatDate(date: string) {
    const d = new Date(date);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    const minutes = Math.floor(diff / (1000 * 60));
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (minutes < 1) return 'Now';
    if (minutes < 60) return `${minutes} minutes ago`;
    if (hours < 24) return `${hours} hours ago`;
    if (days < 7) return `${days} days ago`;
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }
  
  function getNoteClass(post: any) {
    if (post.share_type === 'prayer' || post.prayer) return 'prayer-request-note';
    if (post.share_type === 'praise') return 'praise-note';
    if (post.share_type === 'testimony') return 'testimony-note';
    if (post.gratitude?.length > 0) return 'gratitude-note';
    return '';
  }
  
  function getOnlineCount() {
    // In a real app, this would come from presence tracking
    return Math.floor(Math.random() * 20) + 5;
  }
</script>

<div class="prayer-room-container">
  <!-- Ambient candle lights -->
  <div class="candle-light"></div>
  <div class="candle-light"></div>
  <div class="candle-light"></div>
  <div class="candle-light"></div>
  
  <!-- Header -->
  <div class="sanctuary-header">
    <h1 class="sanctuary-title">✝ COMMUNITY PRAYER WALL ✝</h1>
    <p class="sanctuary-verse">"Bear one another's burdens, and so fulfill the law of Christ" - Galatians 6:2</p>
    <div class="souls-present">
      <div class="soul-indicator"></div>
      <span>{getOnlineCount()} souls present</span>
    </div>
  </div>
  
  <!-- Filter Pills -->
  <div class="filter-section">
    <button class="filter-pill" class:active={filter === 'all'} on:click={() => { filter = 'all'; loadPosts(); }}>
      All Hearts
    </button>
    <button class="filter-pill" class:active={filter === 'prayer'} on:click={() => { filter = 'prayer'; loadPosts(); }}>
      🙏 Prayers
    </button>
    <button class="filter-pill" class:active={filter === 'testimony'} on:click={() => { filter = 'testimony'; loadPosts(); }}>
      ✨ Testimonies
    </button>
    <button class="filter-pill" class:active={filter === 'praise'} on:click={() => { filter = 'praise'; loadPosts(); }}>
      🎉 Praise
    </button>
    <button class="filter-pill" class:active={filter === 'gratitude'} on:click={() => { filter = 'gratitude'; loadPosts(); }}>
      🌟 Gratitude
    </button>
  </div>
  
  <!-- Prayer Wall -->
  <div class="prayer-wall" class:grid-view={displayMode === 'grid'} class:list-view={displayMode === 'list'}>
    {#if loading}
      <div class="sanctuary-welcome">
        <h2>Gathering prayers...</h2>
      </div>
    {:else if posts.length === 0}
      <div class="sanctuary-welcome">
        <h2>Be the first to share</h2>
        <p>This sacred space awaits your heart's expression</p>
      </div>
    {:else}
      <!-- Welcome Message -->
      <div class="sanctuary-welcome">
        <h2>Welcome to This Sacred Space</h2>
        <p>Where hearts unite in prayer and fellowship</p>
        <p style="margin-top: 10px; font-size: 14px; font-style: italic;">
          "For where two or three are gathered together in my name,<br>
          there am I in the midst of them." - Matthew 18:20
        </p>
      </div>
      
      <!-- Prayer Notes -->
      {#each posts as post, index}
        <div class="prayer-note {getNoteClass(post)}" style:animation-delay="{index * 0.1}s">
          <div class="note-header">
            <span class="note-author">
              {post.is_anonymous ? '🕊️ Anonymous Soul' : post.user_name}
              {#if post.mood}
                <span class="mood-indicator">
                  {post.mood === 'grateful' ? '🙏' : 
                   post.mood === 'joyful' ? '😊' :
                   post.mood === 'peaceful' ? '😌' :
                   post.mood === 'hopeful' ? '✨' :
                   post.mood === 'troubled' ? '😟' :
                   post.mood === 'anxious' ? '😰' :
                   post.mood === 'reflective' ? '🤔' :
                   post.mood === 'seeking' ? '🔍' : ''}
                </span>
              {/if}
            </span>
            <span class="note-time">{formatDate(post.created_at)}</span>
          </div>
          
          <div class="note-content">
            {#if post.content}
              <p class="main-content">{post.content}</p>
            {/if}
            
            {#if post.prayer && post.share_type === 'prayer'}
              <div class="prayer-text">
                <strong>Prayer Request:</strong> {post.prayer}
              </div>
            {/if}
            
            {#if post.gratitude && post.gratitude.length > 0}
              <div class="gratitude-list">
                <strong>Grateful for:</strong>
                {#each post.gratitude as item}
                  <span class="gratitude-item">• {item}</span>
                {/each}
              </div>
            {/if}
          </div>
          
          <div class="prayer-warriors">
            {#each reactions as reaction}
              {#if post.reaction_counts?.[reaction.type] > 0 || post.user_reactions?.includes(reaction.type)}
                <button 
                  class="warrior-count"
                  class:active={post.user_reactions?.includes(reaction.type)}
                  on:click={() => toggleReaction(post.id, reaction.type)}
                >
                  <span>{reaction.emoji}</span>
                  <span>{post.reaction_counts?.[reaction.type] || 0} {reaction.label}</span>
                </button>
              {/if}
            {/each}
            
            {#if !post.reaction_counts || Object.keys(post.reaction_counts).length === 0}
              <button 
                class="warrior-count"
                on:click={() => toggleReaction(post.id, 'amen')}
              >
                <span>🙏</span>
                <span>Be first to pray</span>
              </button>
            {/if}
          </div>
        </div>
      {/each}
    {/if}
  </div>
  
  <!-- Info Bar - Journal entries only -->
  <div class="info-bar">
    <div class="info-content">
      <span>💝 Share your heart from the Journal tab</span>
      <button class="display-toggle" on:click={() => displayMode = displayMode === 'grid' ? 'list' : 'grid'}>
        {displayMode === 'grid' ? '📋 List View' : '🏛️ Grid View'}
      </button>
    </div>
  </div>
</div>

<style>
  .prayer-room-container {
    height: calc(100vh - 120px); /* Account for header and nav */
    display: flex;
    flex-direction: column;
    background: var(--bg-dark); /* Use consistent dark background */
    position: relative;
    overflow: hidden;
  }
  
  /* Ambient light effects */
  .prayer-room-container::before {
    content: '';
    position: absolute;
    top: -50%;
    left: -50%;
    width: 200%;
    height: 200%;
    background: radial-gradient(circle, rgba(255, 223, 186, 0.03) 0%, transparent 70%);
    animation: gentleGlow 20s ease-in-out infinite;
    pointer-events: none;
  }
  
  @keyframes gentleGlow {
    0%, 100% { transform: rotate(0deg) scale(1); opacity: 0.5; }
    50% { transform: rotate(180deg) scale(1.1); opacity: 0.8; }
  }
  
  /* Candle lights floating - more subtle */
  .candle-light {
    position: absolute;
    width: 40px;
    height: 40px;
    background: radial-gradient(circle, rgba(255, 183, 77, 0.2), transparent);
    border-radius: 50%;
    animation: flicker 3s ease-in-out infinite;
    pointer-events: none;
  }
  
  .candle-light:nth-child(1) { top: 10%; left: 5%; animation-delay: 0s; }
  .candle-light:nth-child(2) { top: 20%; right: 10%; animation-delay: 1s; }
  .candle-light:nth-child(3) { bottom: 30%; left: 8%; animation-delay: 2s; }
  .candle-light:nth-child(4) { bottom: 20%; right: 5%; animation-delay: 0.5s; }
  
  @keyframes flicker {
    0%, 100% { opacity: 0.8; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.1); }
  }
  
  /* Header - Sanctuary entrance */
  .sanctuary-header {
    background: linear-gradient(180deg, rgba(26, 26, 46, 0.95), rgba(26, 26, 46, 0.8));
    backdrop-filter: blur(10px);
    padding: 20px;
    text-align: center;
    border-bottom: 1px solid rgba(255, 223, 186, 0.2);
    position: relative;
    z-index: 10;
  }
  
  .sanctuary-title {
    color: #ffd700;
    font-size: 28px;
    font-weight: 300;
    letter-spacing: 3px;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.5);
    margin-bottom: 8px;
    font-family: 'Georgia', 'Times New Roman', serif;
  }
  
  .sanctuary-verse {
    color: rgba(255, 223, 186, 0.8);
    font-size: 14px;
    font-style: italic;
  }
  
  /* Online souls indicator */
  .souls-present {
    position: absolute;
    top: 20px;
    right: 20px;
    background: rgba(255, 223, 186, 0.1);
    border: 1px solid rgba(255, 223, 186, 0.3);
    padding: 8px 15px;
    border-radius: 20px;
    color: #ffd700;
    font-size: 13px;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  
  .soul-indicator {
    width: 8px;
    height: 8px;
    background: #4caf50;
    border-radius: 50%;
    animation: pulse 2s infinite;
  }
  
  @keyframes pulse {
    0%, 100% { transform: scale(1); opacity: 1; }
    50% { transform: scale(1.2); opacity: 0.7; }
  }
  
  /* Filter Section */
  .filter-section {
    padding: 15px;
    display: flex;
    gap: 10px;
    justify-content: center;
    background: rgba(26, 26, 46, 0.5);
    backdrop-filter: blur(5px);
    border-bottom: 1px solid rgba(255, 223, 186, 0.1);
  }
  
  .filter-pill {
    padding: 8px 16px;
    background: rgba(255, 223, 186, 0.05);
    border: 1px solid rgba(255, 223, 186, 0.2);
    color: rgba(255, 223, 186, 0.7);
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.3s;
    font-size: 14px;
    font-family: 'Georgia', serif;
  }
  
  .filter-pill:hover {
    background: rgba(255, 223, 186, 0.1);
    transform: translateY(-2px);
  }
  
  .filter-pill.active {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 193, 7, 0.2));
    color: #ffd700;
    border-color: rgba(255, 215, 0, 0.4);
  }
  
  /* Messages area - Prayer Wall */
  .prayer-wall {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    position: relative;
    z-index: 5;
    max-width: 1200px;
    width: 100%;
    margin: 0 auto;
  }
  
  .prayer-wall.grid-view {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 1rem;
    align-content: start;
  }
  
  .prayer-wall.list-view {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  
  .list-view .prayer-note {
    max-width: 800px;
    margin: 0 auto;
    width: 100%;
  }
  
  /* Prayer notes/messages */
  .prayer-note {
    background: rgba(255, 255, 255, 0.03); /* Dark mode friendly */
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    padding: 15px;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
    position: relative;
    transition: all 0.3s ease;
    width: 100%;
    animation: fadeInUp 0.5s ease-out both;
  }
  
  @keyframes fadeInUp {
    from {
      opacity: 0;
      transform: translateY(20px) rotate(-1deg);
    }
    to {
      opacity: 1;
      transform: translateY(0) rotate(-1deg);
    }
  }
  
  /* Remove alternating styles for better space usage */
  
  .prayer-note:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 16px rgba(255, 215, 0, 0.2);
    border-color: var(--border-gold-strong);
  }
  
  /* Remove pin emoji for cleaner look */
  
  .note-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
    padding-bottom: 8px;
    border-bottom: 1px solid rgba(0, 0, 0, 0.1);
  }
  
  .note-author {
    font-weight: 600;
    color: var(--text-divine);
    font-size: 14px;
    display: flex;
    align-items: center;
    gap: 5px;
  }
  
  .mood-indicator {
    font-size: 16px;
  }
  
  .note-time {
    font-size: 12px;
    color: var(--text-scripture);
    opacity: 0.8;
  }
  
  .note-content {
    font-size: 14px;
    line-height: 1.5;
    color: var(--text-light);
    font-family: inherit;
  }
  
  .main-content {
    margin-bottom: 8px;
    /* Truncate long text in grid view */
    display: -webkit-box;
    -webkit-line-clamp: 6;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  
  .list-view .main-content {
    -webkit-line-clamp: unset;
    overflow: visible;
  }
  
  .prayer-text {
    background: rgba(138, 43, 226, 0.03);
    padding: 8px;
    border-radius: 5px;
    margin: 8px 0;
    border-left: 2px solid rgba(138, 43, 226, 0.3);
    font-size: 0.9rem;
  }
  
  .gratitude-list {
    background: rgba(255, 215, 0, 0.03);
    padding: 8px;
    border-radius: 5px;
    margin: 8px 0;
    border-left: 2px solid var(--border-gold);
    font-size: 0.9rem;
  }
  
  .gratitude-item {
    display: block;
    margin: 5px 0;
    padding-left: 10px;
  }
  
  /* Special prayer request style */
  .prayer-request-note {
    background: rgba(138, 43, 226, 0.05);
    border-color: rgba(138, 43, 226, 0.3);
  }
  
  .prayer-request-note::after {
    content: '🙏';
    position: absolute;
    right: 10px;
    top: 10px;
    font-size: 18px;
    opacity: 0.5;
  }
  
  /* Removed unused float animation */
  }
  
  /* Praise report style */
  .praise-note {
    background: rgba(76, 175, 80, 0.05);
    border-color: rgba(76, 175, 80, 0.3);
  }
  
  .praise-note::before {
    content: '✨';
    right: 10px;
    top: 10px;
    left: auto;
  }
  
  .testimony-note {
    background: rgba(156, 39, 176, 0.05);
    border-color: rgba(156, 39, 176, 0.3);
  }
  
  .testimony-note::before {
    content: '💫';
    right: 10px;
    top: 10px;
    left: auto;
  }
  
  .gratitude-note {
    background: rgba(255, 215, 0, 0.05);
    border-color: rgba(255, 215, 0, 0.3);
  }
  
  .gratitude-note::before {
    content: '🌟';
    right: 10px;
    top: 10px;
    left: auto;
  }
  
  /* Removed unused sparkle animation */
  
  /* Prayer warriors (reactions) */
  .prayer-warriors {
    margin-top: 12px;
    padding-top: 10px;
    border-top: 1px solid rgba(0, 0, 0, 0.1);
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }
  
  .warrior-count {
    display: flex;
    align-items: center;
    gap: 5px;
    padding: 4px 8px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 12px;
    font-size: 12px;
    color: var(--text-holy);
    cursor: pointer;
    transition: all 0.3s;
    font-family: inherit;
  }
  
  .warrior-count:hover {
    background: rgba(255, 255, 255, 0.8);
    transform: scale(1.05);
  }
  
  .warrior-count.active {
    background: rgba(255, 215, 0, 0.15);
    border-color: var(--border-gold);
    color: var(--text-divine);
    font-weight: 600;
  }
  
  /* Welcome sanctuary message */
  .sanctuary-welcome {
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 10px;
    padding: 1.5rem;
    text-align: center;
    color: var(--text-divine);
    margin-bottom: 1rem;
    grid-column: 1 / -1; /* Span full width in grid */
  }
  
  .sanctuary-welcome h2 {
    font-size: 24px;
    margin-bottom: 10px;
    text-shadow: 0 0 15px rgba(255, 215, 0, 0.5);
    font-family: 'Georgia', serif;
  }
  
  .sanctuary-welcome p {
    color: rgba(255, 223, 186, 0.9);
    line-height: 1.6;
  }
  
  /* Info Bar */
  .info-bar {
    background: rgba(255, 255, 255, 0.02);
    border-top: 1px solid var(--border-gold);
    padding: 1rem;
    position: relative;
    z-index: 10;
  }
  
  .info-content {
    max-width: 1200px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
    color: var(--text-scripture);
    font-size: 0.9rem;
  }
  
  .display-toggle {
    padding: 0.5rem 1rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    color: var(--text-divine);
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.3s;
    font-size: 0.85rem;
  }
  
  .display-toggle:hover {
    background: rgba(255, 215, 0, 0.2);
    transform: translateY(-2px);
  }
  
  /* Removed unused input styles */
  
  /* Mobile responsiveness */
  @media (max-width: 768px) {
    .sanctuary-title {
      font-size: 20px;
    }
    
    .souls-present {
      position: static;
      margin-top: 10px;
      display: inline-flex;
    }
    
    .prayer-wall {
      padding: 0.75rem;
    }
    
    .prayer-wall.grid-view {
      grid-template-columns: 1fr;
      gap: 0.75rem;
    }
    
    .info-content {
      flex-direction: column;
      gap: 0.75rem;
      text-align: center;
    }
    
    .display-toggle {
      width: 100%;
    }
  }
  
  @media (min-width: 768px) and (max-width: 1024px) {
    .prayer-wall.grid-view {
      grid-template-columns: repeat(2, 1fr);
    }
  }
  
  @media (min-width: 1024px) {
    .prayer-wall.grid-view {
      grid-template-columns: repeat(3, 1fr);
    }
  }
</style>