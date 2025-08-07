<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let posts: any[] = [];
  let loading = true;
  let filter: 'all' | 'prayer' | 'testimony' | 'praise' | 'post' = 'all';
  let newPostContent = '';
  let showNewPost = false;
  let shareType: 'post' | 'prayer' | 'testimony' | 'praise' = 'post';
  let expandedComments: Set<string> = new Set();
  let commentInputs: Map<string, string> = new Map();
  
  const moodEmojis = {
    grateful: '🙏',
    peaceful: '😌',
    joyful: '😊',
    hopeful: '✨',
    reflective: '🤔',
    troubled: '😟',
    anxious: '😰',
    seeking: '🔍'
  };
  
  const reactions = [
    { type: 'amen', emoji: '🙏', label: 'Amen' },
    { type: 'praying', emoji: '🤲', label: 'Praying' },
    { type: 'hallelujah', emoji: '🎉', label: 'Hallelujah' },
    { type: 'love', emoji: '❤️', label: 'Love' },
    { type: 'strength', emoji: '💪', label: 'Strength' }
  ];
  
  onMount(async () => {
    await loadPosts();
    
    // Subscribe to real-time updates
    const channel = supabase
      .channel('community_posts')
      .on('postgres_changes', 
        { event: '*', schema: 'public', table: 'community_posts' },
        () => loadPosts()
      )
      .subscribe();
    
    return () => {
      supabase.removeChannel(channel);
    };
  });
  
  async function loadPosts() {
    loading = true;
    
    let query = supabase
      .from('community_posts')
      .select(`
        *,
        reactions (count),
        encouragements (
          id,
          content,
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
    
    if (filter !== 'all') {
      query = query.eq('share_type', filter);
    }
    
    const { data, error } = await query;
    
    if (error) {
      console.error('Error loading posts:', error);
    } else {
      posts = data || [];
    }
    
    loading = false;
  }
  
  async function createPost() {
    if (!newPostContent.trim()) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('community_posts')
      .insert({
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        content: newPostContent,
        share_type: shareType,
        is_anonymous: false
      });
    
    if (!error) {
      newPostContent = '';
      showNewPost = false;
      await loadPosts();
    }
  }
  
  async function addReaction(postId: string, reactionType: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('reactions')
      .insert({
        post_id: postId,
        user_id: user.id,
        reaction_type: reactionType
      });
    
    if (!error) {
      await loadPosts();
    }
  }
  
  async function addComment(postId: string) {
    const comment = commentInputs.get(postId);
    if (!comment?.trim()) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('encouragements')
      .insert({
        post_id: postId,
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        content: comment
      });
    
    if (!error) {
      commentInputs.set(postId, '');
      await loadPosts();
    }
  }
  
  async function commitToPray(prayerId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('prayer_warriors')
      .insert({
        prayer_id: prayerId,
        user_id: user.id
      });
    
    if (!error) {
      await loadPosts();
    }
  }
  
  function toggleComments(postId: string) {
    if (expandedComments.has(postId)) {
      expandedComments.delete(postId);
    } else {
      expandedComments.add(postId);
    }
    expandedComments = expandedComments;
  }
  
  function formatDate(date: string) {
    const d = new Date(date);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    const minutes = Math.floor(diff / (1000 * 60));
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m`;
    if (hours < 24) return `${hours}h`;
    if (days < 7) return `${days}d`;
    return d.toLocaleDateString();
  }
  
  function getInitials(name: string) {
    return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
</script>

<div class="community-container">
  <!-- Create Post Section -->
  <div class="create-post-card">
    {#if !showNewPost}
      <button class="create-post-trigger" on:click={() => showNewPost = true}>
        <div class="avatar-glow">
          {#if $userInfo?.name}
            {getInitials($userInfo.name)}
          {:else}
            ✝️
          {/if}
        </div>
        <span class="create-prompt">Share what's on your heart...</span>
      </button>
    {:else}
      <div class="new-post-form">
        <div class="post-type-selector">
          <button 
            class:active={shareType === 'post'}
            on:click={() => shareType = 'post'}
          >
            💭 Thought
          </button>
          <button 
            class:active={shareType === 'prayer'}
            on:click={() => shareType = 'prayer'}
          >
            🙏 Prayer
          </button>
          <button 
            class:active={shareType === 'testimony'}
            on:click={() => shareType = 'testimony'}
          >
            ✨ Testimony
          </button>
          <button 
            class:active={shareType === 'praise'}
            on:click={() => shareType = 'praise'}
          >
            🎉 Praise
          </button>
        </div>
        
        <textarea 
          bind:value={newPostContent}
          placeholder={shareType === 'prayer' ? 'Share your prayer request...' : 
                      shareType === 'testimony' ? 'Share your testimony...' :
                      shareType === 'praise' ? 'Share your praise report...' :
                      'What is God doing in your life?'}
          rows="3"
        ></textarea>
        
        <div class="post-actions-bar">
          <button class="cancel-btn" on:click={() => { showNewPost = false; newPostContent = ''; }}>
            Cancel
          </button>
          <button class="submit-btn" on:click={createPost}>
            Share with Community
          </button>
        </div>
      </div>
    {/if}
  </div>
  
  <!-- Filter Tabs -->
  <div class="filter-tabs">
    <button 
      class:active={filter === 'all'} 
      on:click={() => { filter = 'all'; loadPosts(); }}
    >
      <span class="tab-icon">✨</span>
      <span>All Posts</span>
    </button>
    <button 
      class:active={filter === 'prayer'} 
      on:click={() => { filter = 'prayer'; loadPosts(); }}
    >
      <span class="tab-icon">🙏</span>
      <span>Prayers</span>
    </button>
    <button 
      class:active={filter === 'testimony'} 
      on:click={() => { filter = 'testimony'; loadPosts(); }}
    >
      <span class="tab-icon">🕊️</span>
      <span>Testimonies</span>
    </button>
    <button 
      class:active={filter === 'praise'} 
      on:click={() => { filter = 'praise'; loadPosts(); }}
    >
      <span class="tab-icon">🎉</span>
      <span>Praise</span>
    </button>
  </div>
  
  <!-- Posts Feed -->
  {#if loading}
    <div class="loading-divine">
      <div class="loading-spinner"></div>
      <p>Loading community posts...</p>
    </div>
  {:else if posts.length === 0}
    <div class="empty-feed">
      <div class="empty-icon">🕊️</div>
      <h3>No posts yet</h3>
      <p>Be the first to share and inspire the community!</p>
    </div>
  {:else}
    <div class="posts-feed">
      {#each posts as post}
        <div class="post-illuminated" class:prayer-post={post.share_type === 'prayer'}>
          <!-- Post Header -->
          <div class="post-header">
            <div class="author-section">
              <div class="author-avatar">
                {#if post.is_anonymous}
                  🕊️
                {:else}
                  {getInitials(post.user_name || 'Anonymous')}
                {/if}
              </div>
              <div class="author-info">
                <div class="author-name">
                  {post.is_anonymous ? 'Anonymous Soul' : post.user_name || 'Fellow Believer'}
                  {#if post.mood}
                    <span class="mood-badge">{moodEmojis[post.mood]}</span>
                  {/if}
                </div>
                <div class="post-timestamp">
                  {formatDate(post.created_at)}
                  <span class="separator">•</span>
                  <span class="post-badge {post.share_type}">{post.share_type}</span>
                </div>
              </div>
            </div>
            <button class="more-options">⋮</button>
          </div>
          
          <!-- Post Content -->
          <div class="post-body">
            {#if post.content}
              <div class="post-text">
                {post.content}
              </div>
            {/if}
            
            {#if post.gratitude && post.gratitude.length > 0}
              <div class="gratitude-box">
                <div class="gratitude-header">🙏 Grateful For:</div>
                <div class="gratitude-items">
                  {#each post.gratitude as item}
                    <span class="gratitude-tag">{item}</span>
                  {/each}
                </div>
              </div>
            {/if}
            
            {#if post.prayer}
              <div class="prayer-box">
                <div class="prayer-header">🕊️ Prayer Request</div>
                <div class="prayer-text">{post.prayer}</div>
              </div>
            {/if}
            
            {#if post.share_type === 'prayer' && post.prayer_wall?.[0]}
              <div class="prayer-status">
                {#if post.prayer_wall[0].is_urgent}
                  <span class="urgent-badge">🔥 URGENT PRAYER</span>
                {/if}
                {#if post.prayer_wall[0].is_answered}
                  <span class="answered-badge">✅ PRAYER ANSWERED!</span>
                {:else}
                  <div class="prayer-warriors">
                    <button 
                      class="pray-commit-btn"
                      on:click={() => commitToPray(post.prayer_wall[0].id)}
                    >
                      🤲 I'm Praying
                    </button>
                    <span class="warrior-count">
                      {post.prayer_wall[0].prayer_warriors?.[0]?.count || 0} people praying
                    </span>
                  </div>
                {/if}
              </div>
            {/if}
          </div>
          
          <!-- Reactions Bar -->
          <div class="reactions-bar">
            <div class="reaction-buttons">
              {#each reactions as reaction}
                <button 
                  class="reaction-btn"
                  on:click={() => addReaction(post.id, reaction.type)}
                  title={reaction.label}
                >
                  <span class="reaction-emoji">{reaction.emoji}</span>
                  <span class="reaction-label">{reaction.label}</span>
                </button>
              {/each}
            </div>
            {#if post.reactions?.[0]?.count > 0}
              <div class="reaction-count">
                {post.reactions[0].count} reactions
              </div>
            {/if}
          </div>
          
          <!-- Comments Section -->
          <div class="comments-section">
            <button 
              class="toggle-comments"
              on:click={() => toggleComments(post.id)}
            >
              💬 {post.encouragements?.length || 0} Comments
            </button>
            
            {#if expandedComments.has(post.id)}
              <div class="comments-list">
                {#if post.encouragements && post.encouragements.length > 0}
                  {#each post.encouragements as comment}
                    <div class="comment">
                      <div class="comment-avatar">
                        {getInitials(comment.user_name || 'A')}
                      </div>
                      <div class="comment-content">
                        <div class="comment-author">{comment.user_name}</div>
                        <div class="comment-text">{comment.content}</div>
                        <div class="comment-time">{formatDate(comment.created_at)}</div>
                      </div>
                    </div>
                  {/each}
                {/if}
                
                <div class="add-comment">
                  <input 
                    type="text"
                    placeholder="Write an encouragement..."
                    bind:value={commentInputs[post.id]}
                    on:keydown={(e) => e.key === 'Enter' && addComment(post.id)}
                  />
                  <button on:click={() => addComment(post.id)}>Send</button>
                </div>
              </div>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .community-container {
    max-width: 650px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  /* Create Post Card */
  .create-post-card {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    padding: 1rem;
    margin-bottom: 1.5rem;
    backdrop-filter: blur(10px);
  }
  
  .create-post-trigger {
    display: flex;
    align-items: center;
    gap: 1rem;
    width: 100%;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 25px;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .create-post-trigger:hover {
    background: rgba(255, 215, 0, 0.1);
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.2);
  }
  
  .avatar-glow {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.3), rgba(138, 43, 226, 0.3));
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-weight: bold;
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .create-prompt {
    color: var(--text-scripture);
    font-style: italic;
  }
  
  .new-post-form {
    animation: fadeIn 0.3s ease-out;
  }
  
  .post-type-selector {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
  }
  
  .post-type-selector button {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 20px;
    color: var(--text-holy);
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .post-type-selector button.active {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border-color: transparent;
  }
  
  .new-post-form textarea {
    width: 100%;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    color: var(--text-light);
    font-family: inherit;
    font-size: 1rem;
    resize: vertical;
  }
  
  .new-post-form textarea::placeholder {
    color: var(--text-scripture);
  }
  
  .post-actions-bar {
    display: flex;
    justify-content: flex-end;
    gap: 0.5rem;
    margin-top: 1rem;
  }
  
  .cancel-btn {
    padding: 0.5rem 1rem;
    background: transparent;
    border: 1px solid var(--border-gold);
    border-radius: 6px;
    color: var(--text-holy);
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .submit-btn {
    padding: 0.5rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    border: none;
    border-radius: 6px;
    color: var(--bg-dark);
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .submit-btn:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow-divine-strong);
  }
  
  /* Filter Tabs */
  .filter-tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 2rem;
    padding: 0.75rem;
    background: rgba(15, 15, 30, 0.5);
    border-radius: 12px;
    backdrop-filter: blur(10px);
  }
  
  .filter-tabs button {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    padding: 0.75rem;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 8px;
    color: var(--text-holy);
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .filter-tabs button:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
  }
  
  .filter-tabs button.active {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(30, 144, 255, 0.2));
    border-color: var(--border-gold);
    color: var(--text-divine);
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.2);
  }
  
  .tab-icon {
    font-size: 1.2rem;
  }
  
  /* Posts Feed */
  .posts-feed {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  
  .post-illuminated {
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.03), rgba(255, 255, 255, 0.01));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    overflow: hidden;
    transition: all 0.3s;
    animation: fadeIn 0.5s ease-out;
  }
  
  .post-illuminated:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 30px rgba(255, 215, 0, 0.15);
  }
  
  .post-illuminated.prayer-post {
    border-left: 3px solid var(--primary-purple);
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.03));
  }
  
  /* Post Header */
  .post-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    border-bottom: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .author-section {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  
  .author-avatar {
    width: 45px;
    height: 45px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.2), rgba(138, 43, 226, 0.2));
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-weight: bold;
    font-size: 1.1rem;
    box-shadow: 0 0 20px rgba(138, 43, 226, 0.3);
  }
  
  .author-info {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }
  
  .author-name {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.95rem;
  }
  
  .mood-badge {
    margin-left: 0.5rem;
    font-size: 1rem;
  }
  
  .post-timestamp {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--text-scripture);
    font-size: 0.85rem;
  }
  
  .separator {
    opacity: 0.5;
  }
  
  .post-badge {
    padding: 0.15rem 0.5rem;
    border-radius: 10px;
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
  }
  
  .post-badge.prayer {
    background: rgba(138, 43, 226, 0.2);
    color: var(--primary-purple-light);
  }
  
  .post-badge.testimony {
    background: rgba(255, 152, 0, 0.2);
    color: var(--primary-orange);
  }
  
  .post-badge.praise {
    background: rgba(76, 175, 80, 0.2);
    color: #4caf50;
  }
  
  .post-badge.post {
    background: rgba(255, 255, 255, 0.1);
    color: var(--text-holy);
  }
  
  .more-options {
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0.5rem;
    transition: all 0.3s;
  }
  
  .more-options:hover {
    color: var(--text-divine);
  }
  
  /* Post Body */
  .post-body {
    padding: 1rem;
  }
  
  .post-text {
    color: var(--text-light);
    line-height: 1.6;
    margin-bottom: 1rem;
  }
  
  .gratitude-box {
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 0.75rem;
    margin-bottom: 1rem;
  }
  
  .gratitude-header {
    color: var(--text-divine);
    font-weight: 600;
    margin-bottom: 0.5rem;
  }
  
  .gratitude-items {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  
  .gratitude-tag {
    padding: 0.25rem 0.75rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    border-radius: 15px;
    color: var(--text-holy);
    font-size: 0.9rem;
  }
  
  .prayer-box {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(30, 144, 255, 0.05));
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  
  .prayer-header {
    color: var(--primary-purple-light);
    font-weight: 600;
    margin-bottom: 0.5rem;
  }
  
  .prayer-text {
    color: var(--text-light);
    font-style: italic;
    line-height: 1.6;
  }
  
  .prayer-status {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.75rem;
    background: rgba(138, 43, 226, 0.05);
    border-radius: 8px;
  }
  
  .urgent-badge {
    color: #ff6b6b;
    font-weight: 600;
    font-size: 0.9rem;
  }
  
  .answered-badge {
    color: #4caf50;
    font-weight: 600;
    font-size: 0.9rem;
  }
  
  .prayer-warriors {
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  
  .pray-commit-btn {
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, var(--primary-purple), var(--primary-blue));
    border: none;
    border-radius: 20px;
    color: white;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .pray-commit-btn:hover {
    transform: scale(1.05);
    box-shadow: 0 4px 20px rgba(138, 43, 226, 0.4);
  }
  
  .warrior-count {
    color: var(--text-scripture);
    font-size: 0.9rem;
  }
  
  /* Reactions Bar */
  .reactions-bar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.75rem 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
    border-bottom: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .reaction-buttons {
    display: flex;
    gap: 0.25rem;
  }
  
  .reaction-btn {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.35rem 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid transparent;
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .reaction-btn:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
    transform: scale(1.05);
  }
  
  .reaction-emoji {
    font-size: 1.1rem;
  }
  
  .reaction-label {
    color: var(--text-holy);
    font-size: 0.85rem;
    display: none;
  }
  
  .reaction-btn:hover .reaction-label {
    display: inline;
  }
  
  .reaction-count {
    color: var(--text-scripture);
    font-size: 0.85rem;
  }
  
  /* Comments Section */
  .comments-section {
    padding: 0.75rem 1rem;
  }
  
  .toggle-comments {
    background: none;
    border: none;
    color: var(--text-holy);
    font-size: 0.9rem;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .toggle-comments:hover {
    color: var(--text-divine);
  }
  
  .comments-list {
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .comment {
    display: flex;
    gap: 0.75rem;
    margin-bottom: 1rem;
  }
  
  .comment-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: rgba(138, 43, 226, 0.2);
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-size: 0.85rem;
    font-weight: bold;
  }
  
  .comment-content {
    flex: 1;
  }
  
  .comment-author {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.9rem;
    margin-bottom: 0.25rem;
  }
  
  .comment-text {
    color: var(--text-light);
    font-size: 0.95rem;
    line-height: 1.4;
  }
  
  .comment-time {
    color: var(--text-scripture);
    font-size: 0.8rem;
    margin-top: 0.25rem;
  }
  
  .add-comment {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
  }
  
  .add-comment input {
    flex: 1;
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 20px;
    color: var(--text-light);
    font-size: 0.9rem;
  }
  
  .add-comment input::placeholder {
    color: var(--text-scripture);
  }
  
  .add-comment button {
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    border: none;
    border-radius: 20px;
    color: var(--bg-dark);
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .add-comment button:hover {
    transform: scale(1.05);
    box-shadow: 0 2px 10px rgba(255, 215, 0, 0.3);
  }
  
  /* Loading and Empty States */
  .loading-divine, .empty-feed {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  .loading-spinner {
    width: 50px;
    height: 50px;
    border: 3px solid rgba(255, 215, 0, 0.2);
    border-top-color: var(--primary-gold);
    border-radius: 50%;
    margin: 0 auto 1rem;
    animation: spin 1s linear infinite;
  }
  
  .empty-icon {
    font-size: 4rem;
    margin-bottom: 1rem;
    filter: drop-shadow(0 0 20px rgba(255, 215, 0, 0.3));
  }
  
  .empty-feed h3 {
    color: var(--text-divine);
    margin-bottom: 0.5rem;
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
  
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
  
  @media (max-width: 600px) {
    .filter-tabs {
      flex-wrap: wrap;
    }
    
    .filter-tabs button span:not(.tab-icon) {
      display: none;
    }
    
    .reaction-label {
      display: none !important;
    }
  }
</style>