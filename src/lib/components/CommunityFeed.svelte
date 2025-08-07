<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let posts: any[] = [];
  let loading = true;
  let filter: 'all' | 'prayer' | 'testimony' | 'praise' | 'post' = 'all';
  
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
        encouragements (count),
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
      alert('Thank you for committing to pray! 🙏');
      await loadPosts();
    }
  }
  
  function formatDate(date: string) {
    const d = new Date(date);
    const now = new Date();
    const diff = now.getTime() - d.getTime();
    const hours = Math.floor(diff / (1000 * 60 * 60));
    
    if (hours < 1) return 'Just now';
    if (hours < 24) return `${hours}h ago`;
    if (hours < 48) return 'Yesterday';
    return d.toLocaleDateString();
  }
</script>

<div class="community-feed">
  <div class="feed-header">
    <h2>🌟 Community Feed</h2>
    <div class="filters">
      <button 
        class:active={filter === 'all'} 
        on:click={() => { filter = 'all'; loadPosts(); }}
      >
        All
      </button>
      <button 
        class:active={filter === 'prayer'} 
        on:click={() => { filter = 'prayer'; loadPosts(); }}
      >
        🙏 Prayers
      </button>
      <button 
        class:active={filter === 'testimony'} 
        on:click={() => { filter = 'testimony'; loadPosts(); }}
      >
        ✨ Testimonies
      </button>
      <button 
        class:active={filter === 'praise'} 
        on:click={() => { filter = 'praise'; loadPosts(); }}
      >
        🎉 Praise
      </button>
    </div>
  </div>
  
  {#if loading}
    <div class="loading">Loading community posts...</div>
  {:else if posts.length === 0}
    <div class="empty">No posts yet. Be the first to share!</div>
  {:else}
    <div class="posts">
      {#each posts as post}
        <div class="post-card" class:prayer={post.share_type === 'prayer'}>
          <div class="post-header">
            <div class="user-info">
              {#if post.is_anonymous}
                <span class="user-name">Anonymous</span>
              {:else}
                <span class="user-name">{post.user_name || 'A Brother/Sister'}</span>
              {/if}
              {#if post.mood}
                <span class="mood">{moodEmojis[post.mood]} {post.mood}</span>
              {/if}
            </div>
            <div class="post-meta">
              <span class="post-type {post.share_type}">{post.share_type}</span>
              <span class="time">{formatDate(post.created_at)}</span>
            </div>
          </div>
          
          {#if post.content}
            <div class="post-content">
              {post.content}
            </div>
          {/if}
          
          {#if post.gratitude && post.gratitude.length > 0}
            <div class="gratitude-list">
              <strong>Grateful for:</strong>
              <ul>
                {#each post.gratitude as item}
                  <li>{item}</li>
                {/each}
              </ul>
            </div>
          {/if}
          
          {#if post.prayer}
            <div class="prayer-content">
              <strong>Prayer:</strong>
              <p>{post.prayer}</p>
            </div>
          {/if}
          
          {#if post.share_type === 'prayer' && post.prayer_wall?.[0]}
            <div class="prayer-actions">
              {#if post.prayer_wall[0].is_urgent}
                <span class="urgent">🚨 URGENT</span>
              {/if}
              {#if !post.prayer_wall[0].is_answered}
                <button 
                  class="pray-btn"
                  on:click={() => commitToPray(post.prayer_wall[0].id)}
                >
                  🤲 Commit to Pray ({post.prayer_wall[0].prayer_warriors?.[0]?.count || 0} praying)
                </button>
              {:else}
                <span class="answered">✅ ANSWERED!</span>
              {/if}
            </div>
          {/if}
          
          <div class="post-actions">
            <div class="reactions">
              {#each reactions as reaction}
                <button 
                  class="reaction-btn"
                  on:click={() => addReaction(post.id, reaction.type)}
                  title={reaction.label}
                >
                  {reaction.emoji}
                </button>
              {/each}
            </div>
            <button class="comment-btn">
              💬 Encourage ({post.encouragements?.[0]?.count || 0})
            </button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .community-feed {
    max-width: 700px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .feed-header {
    margin-bottom: 2rem;
  }
  
  .feed-header h2 {
    margin: 0 0 1rem 0;
    text-align: center;
  }
  
  .filters {
    display: flex;
    gap: 0.5rem;
    justify-content: center;
  }
  
  .filters button {
    padding: 0.5rem 1rem;
    border: 1px solid #ddd;
    background: white;
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .filters button:hover {
    background: #f5f5f5;
  }
  
  .filters button.active {
    background: #667eea;
    color: white;
    border-color: #667eea;
  }
  
  .loading, .empty {
    text-align: center;
    padding: 3rem;
    color: #666;
  }
  
  .posts {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  
  .post-card {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    transition: transform 0.2s;
  }
  
  .post-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  }
  
  .post-card.prayer {
    border-left: 4px solid #667eea;
  }
  
  .post-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 1rem;
  }
  
  .user-info {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .user-name {
    font-weight: 600;
  }
  
  .mood {
    font-size: 0.9rem;
    color: #666;
  }
  
  .post-meta {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .post-type {
    padding: 0.25rem 0.5rem;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: 600;
    text-transform: uppercase;
  }
  
  .post-type.prayer {
    background: #e8eaf6;
    color: #667eea;
  }
  
  .post-type.testimony {
    background: #fff3e0;
    color: #ff9800;
  }
  
  .post-type.praise {
    background: #e8f5e9;
    color: #4caf50;
  }
  
  .post-type.post {
    background: #f5f5f5;
    color: #666;
  }
  
  .time {
    font-size: 0.85rem;
    color: #999;
  }
  
  .post-content {
    margin-bottom: 1rem;
    line-height: 1.6;
  }
  
  .gratitude-list {
    background: #f8f9fa;
    padding: 1rem;
    border-radius: 8px;
    margin-bottom: 1rem;
  }
  
  .gratitude-list ul {
    margin: 0.5rem 0 0 1.5rem;
    padding: 0;
  }
  
  .prayer-content {
    background: #f8f9ff;
    padding: 1rem;
    border-radius: 8px;
    margin-bottom: 1rem;
  }
  
  .prayer-content p {
    margin: 0.5rem 0 0 0;
    font-style: italic;
  }
  
  .prayer-actions {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .urgent {
    color: #f44336;
    font-weight: 600;
  }
  
  .answered {
    color: #4caf50;
    font-weight: 600;
  }
  
  .pray-btn {
    padding: 0.5rem 1rem;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .pray-btn:hover {
    background: #5a72d8;
    transform: scale(1.05);
  }
  
  .post-actions {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-top: 1rem;
    border-top: 1px solid #f0f0f0;
  }
  
  .reactions {
    display: flex;
    gap: 0.25rem;
  }
  
  .reaction-btn {
    padding: 0.25rem 0.5rem;
    background: #f5f5f5;
    border: none;
    border-radius: 12px;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 1.2rem;
  }
  
  .reaction-btn:hover {
    background: #e0e0e0;
    transform: scale(1.1);
  }
  
  .comment-btn {
    padding: 0.5rem 1rem;
    background: transparent;
    border: 1px solid #ddd;
    border-radius: 20px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .comment-btn:hover {
    background: #f5f5f5;
  }
</style>