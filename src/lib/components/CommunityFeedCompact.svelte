<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let posts: any[] = [];
  let loading = true;
  let filter: 'all' | 'prayer' | 'testimony' | 'praise' | 'post' | 'my-posts' = 'all';
  let expandedPosts: Set<string> = new Set();
  let commentInputs: { [key: string]: string } = {};
  
  const moodEmojis = {
    grateful: '🙏', peaceful: '😌', joyful: '😊', hopeful: '✨',
    reflective: '🤔', troubled: '😟', anxious: '😰', seeking: '🔍'
  };
  
  const reactions = [
    { type: 'amen', emoji: '🙏' },
    { type: 'praying', emoji: '🤲' },
    { type: 'hallelujah', emoji: '🎉' },
    { type: 'love', emoji: '❤️' },
    { type: 'strength', emoji: '💪' }
  ];
  
  onMount(async () => {
    await loadPosts();
    
    // Subscribe to both posts and encouragements changes
    const channel = supabase
      .channel('community_feed')
      .on('postgres_changes', 
        { event: '*', schema: 'public', table: 'community_posts' },
        () => loadPosts()
      )
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'encouragements' },
        () => loadPosts()
      )
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'reactions' },
        () => loadPosts()
      )
      .subscribe();
    
    return () => {
      supabase.removeChannel(channel);
    };
  });
  
  async function loadPosts() {
    loading = true;
    
    // Preserve expanded posts state
    const previouslyExpanded = new Set(expandedPosts);
    
    let query = supabase
      .from('community_posts')
      .select(`
        *,
        reactions!left (
          reaction,
          count,
          user_id
        ),
        encouragements (
          id,
          message,
          user_name,
          created_at
        ),
        prayer_wall (
          id,
          category,
          is_urgent,
          is_answered,
          prayer_warriors (count)
        )
      `)
      .order('created_at', { ascending: false });
    
    if (filter === 'my-posts') {
      const user = await authStore.getUser();
      if (user) {
        query = query.eq('user_id', user.id);
      }
    } else if (filter !== 'all') {
      query = query.eq('share_type', filter);
    }
    
    const { data, error } = await query;
    
    if (error) {
      console.error('Error loading posts:', error);
    } else {
      // Process posts to group reactions by type
      const user = await authStore.getUser();
      posts = (data || []).map(post => {
        // Group reactions by type and count them
        const reactionGroups = {};
        const userReactions = [];
        
        if (post.reactions) {
          post.reactions.forEach(r => {
            if (!reactionGroups[r.reaction]) {
              reactionGroups[r.reaction] = { reaction: r.reaction, count: 0 };
            }
            reactionGroups[r.reaction].count++;
            
            if (r.user_id === user?.id) {
              userReactions.push(r.reaction);
            }
          });
        }
        
        return {
          ...post,
          reactions: Object.values(reactionGroups),
          user_reactions: userReactions
        };
      });
      
      // Restore expanded state for posts that still exist
      expandedPosts = new Set([...previouslyExpanded].filter(id => 
        posts.some(post => post.id === id)
      ));
    }
    
    loading = false;
  }
  
  async function addReaction(postId: string, reactionType: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Find the post
    const postIndex = posts.findIndex(p => p.id === postId);
    if (postIndex === -1) return;
    
    // Update locally first for immediate feedback
    const post = posts[postIndex];
    const existingReactionIndex = post.reactions.findIndex(r => r.reaction === reactionType);
    
    if (existingReactionIndex !== -1) {
      // Increment count for existing reaction type
      post.reactions[existingReactionIndex].count++;
    } else {
      // Add new reaction type
      post.reactions.push({ reaction: reactionType, count: 1 });
    }
    
    // Add to user's reactions
    if (!post.user_reactions.includes(reactionType)) {
      post.user_reactions.push(reactionType);
    }
    
    // Trigger Svelte reactivity
    posts = posts;
    
    // Then persist to database (fire and forget)
    await supabase
      .from('reactions')
      .insert({
        post_id: postId,
        user_id: user.id,
        reaction_type: reactionType
      });
  }
  
  async function addComment(postId: string) {
    const comment = commentInputs[postId];
    if (!comment?.trim()) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    // Find the post
    const postIndex = posts.findIndex(p => p.id === postId);
    if (postIndex === -1) return;
    
    // Create new comment object
    const newComment = {
      id: crypto.randomUUID(),
      message: comment,
      user_name: $userInfo?.name || user.email?.split('@')[0],
      created_at: new Date().toISOString()
    };
    
    // Update locally for immediate feedback
    if (!posts[postIndex].encouragements) {
      posts[postIndex].encouragements = [];
    }
    posts[postIndex].encouragements.push(newComment);
    
    // Clear input and trigger reactivity
    commentInputs[postId] = '';
    posts = posts;
    
    // Then persist to database
    const { error } = await supabase
      .from('encouragements')
      .insert({
        post_id: postId,
        user_id: user.id,
        user_name: newComment.user_name,
        message: comment
      });
    
    if (error) {
      console.error('Error adding comment:', error);
      // Revert on error
      posts[postIndex].encouragements.pop();
      posts = posts;
      commentInputs[postId] = comment;
    }
  }
  
  async function commitToPray(prayerId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Find the post with this prayer
    const postIndex = posts.findIndex(p => p.prayer_wall?.[0]?.id === prayerId);
    if (postIndex === -1) return;
    
    // Update locally for immediate feedback
    if (posts[postIndex].prayer_wall[0].prayer_warriors) {
      posts[postIndex].prayer_wall[0].prayer_warriors[0].count++;
    } else {
      posts[postIndex].prayer_wall[0].prayer_warriors = [{ count: 1 }];
    }
    
    // Trigger reactivity
    posts = posts;
    
    // Then persist to database
    await supabase
      .from('prayer_warriors')
      .insert({
        prayer_id: prayerId,
        user_id: user.id
      });
  }
  
  function togglePost(postId: string) {
    if (expandedPosts.has(postId)) {
      expandedPosts.delete(postId);
    } else {
      expandedPosts.add(postId);
    }
    expandedPosts = expandedPosts;
  }
  
  function formatDate(date: string) {
    const d = new Date(date);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    const minutes = Math.floor(diff / (1000 * 60));
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (minutes < 1) return 'Now';
    if (minutes < 60) return `${minutes}m`;
    if (hours < 24) return `${hours}h`;
    if (days < 7) return `${days}d`;
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }
  
  function getInitials(name: string) {
    return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
  
  function truncateText(text: string, limit: number = 150) {
    if (text.length <= limit) return text;
    return text.slice(0, limit) + '...';
  }
</script>

<div class="community-compact">
  <!-- Info Banner -->
  <div class="info-banner">
    <h3>🌟 Community Fellowship</h3>
    <p>Share your journey from the Journal tab</p>
  </div>
  
  <!-- Filter Pills -->
  <div class="filter-pills">
    <button class:active={filter === 'all'} on:click={() => { filter = 'all'; loadPosts(); }}>
      All
    </button>
    <button class:active={filter === 'my-posts'} on:click={() => { filter = 'my-posts'; loadPosts(); }}>
      My Posts
    </button>
    <button class:active={filter === 'prayer'} on:click={() => { filter = 'prayer'; loadPosts(); }}>
      Prayers
    </button>
    <button class:active={filter === 'testimony'} on:click={() => { filter = 'testimony'; loadPosts(); }}>
      Testimonies
    </button>
    <button class:active={filter === 'praise'} on:click={() => { filter = 'praise'; loadPosts(); }}>
      Praise
    </button>
  </div>
  
  <!-- Posts Feed -->
  {#if loading}
    <div class="loading">Loading...</div>
  {:else if posts.length === 0}
    <div class="empty">No posts yet in this category</div>
  {:else}
    <div class="posts-compact">
      {#each posts as post}
        <div class="post-card" class:expanded={expandedPosts.has(post.id)}>
          <!-- Visual Reactions Bar -->
          {#if post.reactions && post.reactions.length > 0}
            <div class="reactions-visual-bar">
              {#each post.reactions as reactionGroup}
                {#if reactionGroup.count > 0}
                  <div class="reaction-group">
                    {#each Array(Math.min(reactionGroup.count, 10)) as _, i}
                      <span 
                        class="reaction-emoji" 
                        style="animation-delay: {i * 0.05}s; z-index: {10 - i}"
                      >
                        {reactions.find(r => r.type === reactionGroup.reaction)?.emoji || '🙏'}
                      </span>
                    {/each}
                    {#if reactionGroup.count > 10}
                      <span class="reaction-overflow">+{reactionGroup.count - 10}</span>
                    {/if}
                  </div>
                {/if}
              {/each}
            </div>
          {/if}
          
          <!-- Compact Header -->
          <div class="post-header">
            <div class="author">
              <div class="avatar">{post.is_anonymous ? '🕊️' : getInitials(post.user_name || 'User')}</div>
              <div class="author-info">
                <span class="author-name">
                  {post.is_anonymous ? 'Anonymous' : post.user_name || 'Fellow Believer'}
                  {#if post.mood}
                    <span class="mood">{moodEmojis[post.mood]}</span>
                  {/if}
                </span>
                <span class="timestamp">{formatDate(post.created_at)} • {post.share_type}</span>
              </div>
            </div>
            {#if post.share_type === 'prayer' && post.prayer_wall?.[0]}
              {#if post.prayer_wall[0].is_urgent}
                <span class="urgent-badge">🔥 URGENT</span>
              {/if}
              {#if post.prayer_wall[0].is_answered}
                <span class="answered-badge">✅ ANSWERED</span>
              {/if}
            {/if}
          </div>
          
          <!-- Compact Content -->
          <div class="post-content">
            {#if !expandedPosts.has(post.id)}
              <p class="content-preview">
                {truncateText(post.content || post.prayer || '')}
                {#if (post.content?.length > 150 || post.prayer?.length > 150)}
                  <button class="read-more" on:click={() => togglePost(post.id)}>
                    Read more
                  </button>
                {/if}
              </p>
            {:else}
              <p class="content-full">{post.content || post.prayer}</p>
              {#if post.gratitude && post.gratitude.length > 0}
                <div class="gratitude-compact">
                  <strong>Grateful for:</strong>
                  {#each post.gratitude as item}
                    <span class="gratitude-tag">{item}</span>
                  {/each}
                </div>
              {/if}
              <button class="read-less" on:click={() => togglePost(post.id)}>
                Show less
              </button>
            {/if}
          </div>
          
          <!-- Compact Actions Bar -->
          <div class="actions-bar">
            <div class="reactions-compact">
              {#each reactions as reaction}
                <button 
                  class="reaction-btn"
                  class:active={post.user_reactions?.includes(reaction.type)}
                  on:click={() => addReaction(post.id, reaction.type)}
                  title={reaction.type}
                >
                  {reaction.emoji}
                  {#if post.reactions?.find(r => r.reaction === reaction.type)?.count > 0}
                    <span class="reaction-mini-count">
                      {post.reactions.find(r => r.reaction === reaction.type).count}
                    </span>
                  {/if}
                </button>
              {/each}
            </div>
            
            <button 
              class="comment-toggle"
              on:click={() => togglePost(post.id)}
            >
              💬 {post.encouragements?.length || 0}
            </button>
            
            {#if post.share_type === 'prayer' && post.prayer_wall?.[0] && !post.prayer_wall[0].is_answered}
              <button 
                class="pray-btn"
                on:click={() => commitToPray(post.prayer_wall[0].id)}
              >
                🤲 {post.prayer_wall[0].prayer_warriors?.[0]?.count || 0}
              </button>
            {/if}
          </div>
          
          <!-- Comments (Only when expanded) -->
          {#if expandedPosts.has(post.id) && post.encouragements?.length > 0}
            <div class="comments-section">
              {#each post.encouragements.slice(0, 3) as comment}
                <div class="comment-compact">
                  <strong>{comment.user_name}:</strong> {comment.message}
                </div>
              {/each}
              {#if post.encouragements.length > 3}
                <span class="more-comments">+{post.encouragements.length - 3} more comments</span>
              {/if}
            </div>
          {/if}
          
          {#if expandedPosts.has(post.id)}
            <div class="comment-input">
              <input 
                type="text"
                placeholder="Add encouragement..."
                bind:value={commentInputs[post.id]}
                on:keydown={(e) => e.key === 'Enter' && addComment(post.id)}
              />
              <button on:click={() => addComment(post.id)}>Send</button>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .community-compact {
    max-width: 650px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .info-banner {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.08), rgba(255, 193, 7, 0.04));
    border: 1px solid var(--border-gold);
    border-radius: 10px;
    padding: 1rem;
    margin-bottom: 1rem;
    text-align: center;
  }
  
  .info-banner h3 {
    color: var(--text-divine);
    margin: 0 0 0.25rem 0;
    font-size: 1.1rem;
  }
  
  .info-banner p {
    color: var(--text-scripture);
    margin: 0;
    font-size: 0.85rem;
  }
  
  .filter-pills {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
    overflow-x: auto;
    padding: 0.5rem;
    background: rgba(15, 15, 30, 0.5);
    border-radius: 8px;
  }
  
  .filter-pills button {
    padding: 0.4rem 0.8rem;
    background: transparent;
    border: 1px solid var(--border-gold);
    border-radius: 20px;
    color: var(--text-holy);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.3s;
    white-space: nowrap;
  }
  
  .filter-pills button.active {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border-color: transparent;
  }
  
  .loading, .empty {
    text-align: center;
    padding: 2rem;
    color: var(--text-scripture);
  }
  
  .posts-compact {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  
  .post-card {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 10px;
    padding: 0.75rem;
    padding-top: 1.25rem;
    transition: all 0.3s;
    position: relative;
    overflow: visible;
  }
  
  /* Visual Reactions Bar */
  .reactions-visual-bar {
    position: absolute;
    top: -10px;
    left: 1rem;
    right: 1rem;
    display: flex;
    gap: 0.75rem;
    z-index: 10;
  }
  
  .reaction-group {
    display: flex;
    align-items: center;
    position: relative;
  }
  
  .reaction-emoji {
    display: inline-flex;
    font-size: 1rem;
    margin-left: -6px;
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.9), rgba(255, 248, 220, 0.9));
    border-radius: 50%;
    width: 22px;
    height: 22px;
    align-items: center;
    justify-content: center;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2), 0 0 0 1px rgba(255, 215, 0, 0.3);
    animation: bounceIn 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55) both;
    position: relative;
  }
  
  .reaction-emoji:first-child {
    margin-left: 0;
  }
  
  .reaction-emoji:hover {
    transform: scale(1.2);
    z-index: 20 !important;
  }
  
  @keyframes bounceIn {
    0% {
      transform: scale(0) translateY(-20px);
      opacity: 0;
    }
    50% {
      transform: scale(1.1) translateY(0);
    }
    100% {
      transform: scale(1) translateY(0);
      opacity: 1;
    }
  }
  
  .reaction-overflow {
    margin-left: 4px;
    font-size: 0.7rem;
    color: var(--text-divine);
    font-weight: 600;
    background: rgba(255, 215, 0, 0.2);
    padding: 2px 6px;
    border-radius: 10px;
    border: 1px solid rgba(255, 215, 0, 0.3);
  }
  
  .post-card:hover {
    background: rgba(255, 255, 255, 0.03);
    box-shadow: 0 4px 12px rgba(255, 215, 0, 0.1);
  }
  
  .post-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
  }
  
  .author {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.2), rgba(138, 43, 226, 0.2));
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-size: 0.85rem;
    font-weight: bold;
  }
  
  .author-info {
    display: flex;
    flex-direction: column;
  }
  
  .author-name {
    color: var(--text-divine);
    font-size: 0.9rem;
    font-weight: 600;
  }
  
  .mood {
    margin-left: 0.25rem;
  }
  
  .timestamp {
    color: var(--text-scripture);
    font-size: 0.75rem;
  }
  
  .urgent-badge, .answered-badge {
    padding: 0.2rem 0.5rem;
    border-radius: 12px;
    font-size: 0.75rem;
    font-weight: bold;
  }
  
  .urgent-badge {
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
  }
  
  .answered-badge {
    background: rgba(76, 175, 80, 0.2);
    color: #4caf50;
  }
  
  .post-content {
    margin-bottom: 0.5rem;
  }
  
  .content-preview, .content-full {
    color: var(--text-light);
    font-size: 0.9rem;
    line-height: 1.4;
    margin: 0;
  }
  
  .read-more, .read-less {
    background: none;
    border: none;
    color: var(--text-divine);
    font-size: 0.85rem;
    cursor: pointer;
    padding: 0;
    margin-left: 0.25rem;
    text-decoration: underline;
  }
  
  .gratitude-compact {
    margin-top: 0.5rem;
    font-size: 0.85rem;
  }
  
  .gratitude-tag {
    display: inline-block;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    padding: 0.15rem 0.4rem;
    border-radius: 10px;
    margin: 0.2rem;
    font-size: 0.8rem;
    color: var(--text-holy);
  }
  
  .actions-bar {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding-top: 0.5rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .reactions-compact {
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }
  
  .reaction-btn {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid transparent;
    border-radius: 12px;
    padding: 0.25rem 0.35rem;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.9rem;
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }
  
  .reaction-btn:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
    transform: scale(1.1);
  }
  
  .reaction-btn.active {
    background: rgba(255, 215, 0, 0.2);
    border-color: var(--border-gold);
  }
  
  .reaction-mini-count {
    font-size: 0.7rem;
    color: var(--text-divine);
    font-weight: 600;
    background: rgba(255, 215, 0, 0.15);
    padding: 1px 4px;
    border-radius: 8px;
  }
  
  .reaction-count {
    color: var(--text-scripture);
    font-size: 0.8rem;
    margin-left: 0.25rem;
  }
  
  .comment-toggle, .pray-btn {
    background: none;
    border: none;
    color: var(--text-holy);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .comment-toggle:hover, .pray-btn:hover {
    color: var(--text-divine);
  }
  
  .comments-section {
    margin-top: 0.75rem;
    padding: 0.5rem;
    background: rgba(255, 255, 255, 0.02);
    border-radius: 6px;
  }
  
  .comment-compact {
    color: var(--text-light);
    font-size: 0.85rem;
    margin-bottom: 0.25rem;
  }
  
  .comment-compact strong {
    color: var(--text-divine);
  }
  
  .more-comments {
    color: var(--text-scripture);
    font-size: 0.8rem;
    font-style: italic;
  }
  
  .comment-input {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }
  
  .comment-input input {
    flex: 1;
    padding: 0.4rem 0.8rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 20px;
    color: var(--text-light);
    font-size: 0.85rem;
  }
  
  .comment-input button {
    padding: 0.4rem 0.8rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    border: none;
    border-radius: 20px;
    color: var(--bg-dark);
    font-size: 0.85rem;
    cursor: pointer;
    font-weight: 600;
  }
  
  @media (max-width: 600px) {
    .filter-pills {
      padding: 0.25rem;
    }
    
    .post-card {
      padding: 0.5rem;
    }
  }
</style>