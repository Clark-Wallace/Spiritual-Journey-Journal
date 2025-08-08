<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let posts: any[] = [];
  let loading = true;
  let filter: 'all' | 'prayer' | 'testimony' | 'praise' | 'gratitude' = 'all';
  let newPost = '';
  let postType: 'prayer' | 'testimony' | 'praise' | 'message' = 'message';
  let isAnonymous = false;
  let subscription: any;
  
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
  
  async function sharePost() {
    if (!newPost.trim()) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('community_posts')
      .insert({
        user_id: user.id,
        user_name: isAnonymous ? 'Anonymous Soul' : ($userInfo?.name || user.email?.split('@')[0]),
        is_anonymous: isAnonymous,
        share_type: postType === 'message' ? 'post' : postType,
        content: newPost,
        mood: null,
        gratitude: null,
        prayer: postType === 'prayer' ? newPost : null
      });
    
    if (error) {
      console.error('Error sharing post:', error);
    } else {
      newPost = '';
      postType = 'message';
      isAnonymous = false;
    }
  }
  
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
  <div class="prayer-wall">
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
  
  <!-- Prayer Altar (Input) -->
  <div class="prayer-altar">
    <div class="prayer-type">
      <span class="type-option" class:active={postType === 'message'} on:click={() => postType = 'message'}>
        Message
      </span>
      <span class="type-option" class:active={postType === 'prayer'} on:click={() => postType = 'prayer'}>
        Prayer Request
      </span>
      <span class="type-option" class:active={postType === 'praise'} on:click={() => postType = 'praise'}>
        Praise Report
      </span>
      <span class="type-option" class:active={postType === 'testimony'} on:click={() => postType = 'testimony'}>
        Testimony
      </span>
    </div>
    
    <div class="altar-container">
      <div class="prayer-input-wrapper">
        <textarea 
          class="prayer-input" 
          placeholder={postType === 'prayer' ? 'Share your prayer request...' :
                      postType === 'praise' ? 'Share your praise report...' :
                      postType === 'testimony' ? 'Share your testimony...' :
                      'Share your heart, lift up a prayer, or encourage a soul...'}
          rows="2"
          bind:value={newPost}
        ></textarea>
      </div>
      <div class="prayer-actions">
        <label class="anonymous-toggle" title="Share anonymously">
          <input type="checkbox" bind:checked={isAnonymous} />
          <span>🕊️</span>
        </label>
        <button class="altar-button send-prayer" on:click={sharePost}>
          Lift Up
        </button>
      </div>
    </div>
  </div>
</div>

<style>
  .prayer-room-container {
    height: calc(100vh - 120px); /* Account for header and nav */
    display: flex;
    flex-direction: column;
    background: linear-gradient(180deg, #1a1a2e 0%, #0f0f1e 50%, #16213e 100%);
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
  
  /* Candle lights floating */
  .candle-light {
    position: absolute;
    width: 60px;
    height: 60px;
    background: radial-gradient(circle, rgba(255, 183, 77, 0.6), transparent);
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
    padding: 30px;
    position: relative;
    z-index: 5;
    display: flex;
    flex-direction: column;
    gap: 20px;
    max-width: 1000px;
    width: 100%;
    margin: 0 auto;
  }
  
  /* Prayer notes/messages */
  .prayer-note {
    background: linear-gradient(135deg, rgba(255, 248, 225, 0.95), rgba(255, 243, 205, 0.95));
    color: #2c3e50;
    padding: 20px;
    border-radius: 8px;
    box-shadow: 
      0 5px 15px rgba(0, 0, 0, 0.3),
      inset 0 1px 0 rgba(255, 255, 255, 0.5);
    position: relative;
    transform: rotate(-1deg);
    transition: all 0.3s ease;
    max-width: 600px;
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
  
  .prayer-note:nth-child(even) {
    align-self: flex-end;
    transform: rotate(1deg);
    background: linear-gradient(135deg, rgba(255, 235, 205, 0.95), rgba(255, 228, 181, 0.95));
  }
  
  .prayer-note:hover {
    transform: rotate(0deg) scale(1.02);
    box-shadow: 
      0 8px 25px rgba(0, 0, 0, 0.4),
      0 0 40px rgba(255, 215, 0, 0.2);
  }
  
  .prayer-note::before {
    content: '📌';
    position: absolute;
    top: -10px;
    left: 20px;
    font-size: 20px;
  }
  
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
    color: #8b4513;
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
    color: #a0522d;
    opacity: 0.8;
  }
  
  .note-content {
    font-size: 16px;
    line-height: 1.6;
    color: #3e2723;
    font-family: 'Georgia', serif;
  }
  
  .main-content {
    margin-bottom: 12px;
  }
  
  .prayer-text {
    background: rgba(138, 43, 226, 0.05);
    padding: 10px;
    border-radius: 5px;
    margin: 10px 0;
    border-left: 3px solid rgba(138, 43, 226, 0.3);
  }
  
  .gratitude-list {
    background: rgba(255, 215, 0, 0.08);
    padding: 10px;
    border-radius: 5px;
    margin: 10px 0;
    border-left: 3px solid #ffd700;
  }
  
  .gratitude-item {
    display: block;
    margin: 5px 0;
    padding-left: 10px;
  }
  
  /* Special prayer request style */
  .prayer-request-note {
    background: linear-gradient(135deg, rgba(255, 193, 7, 0.15), rgba(255, 152, 0, 0.15));
    border: 2px solid rgba(255, 152, 0, 0.3);
    padding-left: 50px;
  }
  
  .prayer-request-note::after {
    content: '🙏';
    position: absolute;
    left: 15px;
    top: 50%;
    transform: translateY(-50%);
    font-size: 24px;
    animation: float 3s ease-in-out infinite;
  }
  
  @keyframes float {
    0%, 100% { transform: translateY(-50%); }
    50% { transform: translateY(-60%); }
  }
  
  /* Praise report style */
  .praise-note {
    background: linear-gradient(135deg, rgba(139, 195, 74, 0.15), rgba(76, 175, 80, 0.15));
    border: 2px solid rgba(76, 175, 80, 0.3);
  }
  
  .praise-note::before {
    content: '✨';
    animation: sparkle 2s ease-in-out infinite;
  }
  
  .testimony-note {
    background: linear-gradient(135deg, rgba(156, 39, 176, 0.1), rgba(103, 58, 183, 0.1));
    border: 2px solid rgba(156, 39, 176, 0.3);
  }
  
  .testimony-note::before {
    content: '💫';
  }
  
  .gratitude-note {
    background: linear-gradient(135deg, rgba(255, 235, 59, 0.15), rgba(255, 193, 7, 0.15));
    border: 2px solid rgba(255, 193, 7, 0.3);
  }
  
  .gratitude-note::before {
    content: '🌟';
  }
  
  @keyframes sparkle {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.7; transform: scale(1.2); }
  }
  
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
    padding: 4px 10px;
    background: rgba(255, 255, 255, 0.5);
    border: 1px solid transparent;
    border-radius: 15px;
    font-size: 13px;
    color: #5d4037;
    cursor: pointer;
    transition: all 0.3s;
    font-family: inherit;
  }
  
  .warrior-count:hover {
    background: rgba(255, 255, 255, 0.8);
    transform: scale(1.05);
  }
  
  .warrior-count.active {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.3), rgba(255, 193, 7, 0.3));
    border-color: rgba(255, 215, 0, 0.5);
    color: #8b4513;
    font-weight: 600;
  }
  
  /* Welcome sanctuary message */
  .sanctuary-welcome {
    background: radial-gradient(ellipse at center, rgba(255, 215, 0, 0.1), transparent);
    border: 1px solid rgba(255, 215, 0, 0.3);
    border-radius: 15px;
    padding: 30px;
    text-align: center;
    color: #ffd700;
    margin-bottom: 20px;
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
  
  /* Input area - Prayer altar */
  .prayer-altar {
    background: linear-gradient(180deg, rgba(26, 26, 46, 0.95), rgba(15, 15, 30, 0.95));
    backdrop-filter: blur(10px);
    border-top: 1px solid rgba(255, 223, 186, 0.2);
    padding: 20px;
    position: relative;
    z-index: 10;
  }
  
  .altar-container {
    max-width: 800px;
    margin: 0 auto;
    display: flex;
    gap: 15px;
    align-items: flex-end;
  }
  
  .prayer-input-wrapper {
    flex: 1;
    background: rgba(255, 248, 225, 0.1);
    border: 1px solid rgba(255, 223, 186, 0.3);
    border-radius: 12px;
    padding: 12px 15px;
    transition: all 0.3s;
  }
  
  .prayer-input-wrapper:focus-within {
    background: rgba(255, 248, 225, 0.15);
    box-shadow: 0 0 30px rgba(255, 215, 0, 0.2);
  }
  
  .prayer-input {
    width: 100%;
    background: none;
    border: none;
    color: #ffd700;
    font-size: 15px;
    font-family: 'Georgia', serif;
    outline: none;
    resize: none;
  }
  
  .prayer-input::placeholder {
    color: rgba(255, 223, 186, 0.5);
  }
  
  .prayer-actions {
    display: flex;
    gap: 10px;
    align-items: center;
  }
  
  .anonymous-toggle {
    display: flex;
    align-items: center;
    cursor: pointer;
    padding: 10px;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid rgba(255, 215, 0, 0.3);
    border-radius: 8px;
    transition: all 0.3s;
  }
  
  .anonymous-toggle:hover {
    background: rgba(255, 215, 0, 0.2);
  }
  
  .anonymous-toggle input {
    display: none;
  }
  
  .anonymous-toggle input:checked + span {
    filter: brightness(1.5);
  }
  
  .altar-button {
    padding: 10px 20px;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 193, 7, 0.2));
    border: 1px solid rgba(255, 215, 0, 0.4);
    color: #ffd700;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.3s;
    font-family: 'Georgia', serif;
  }
  
  .altar-button:hover {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.3), rgba(255, 193, 7, 0.3));
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
    transform: translateY(-2px);
  }
  
  .send-prayer {
    background: linear-gradient(135deg, #ffd700, #ffb300);
    color: #1a1a2e;
    font-weight: 600;
  }
  
  .send-prayer:hover {
    background: linear-gradient(135deg, #ffed4e, #ffc947);
  }
  
  /* Prayer type indicator */
  .prayer-type {
    position: absolute;
    top: -30px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 10px;
    padding: 5px 10px;
    background: rgba(26, 26, 46, 0.8);
    border-radius: 20px;
  }
  
  .type-option {
    padding: 5px 10px;
    border-radius: 15px;
    font-size: 12px;
    cursor: pointer;
    transition: all 0.3s;
    color: rgba(255, 223, 186, 0.6);
  }
  
  .type-option.active {
    background: rgba(255, 215, 0, 0.2);
    color: #ffd700;
  }
  
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
      padding: 15px;
    }
    
    .prayer-note {
      max-width: 100%;
      align-self: stretch !important;
    }
    
    .prayer-type {
      position: static;
      transform: none;
      margin-bottom: 10px;
      justify-content: center;
    }
    
    .altar-container {
      flex-direction: column;
      gap: 10px;
    }
    
    .prayer-actions {
      width: 100%;
      justify-content: space-between;
    }
  }
</style>