<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  import { currentView } from '../stores';
  
  let wallNotes: any[] = [];
  let loading = true;
  let selectedNote: any = null;
  let showNoteDetail = false;
  let showCreatePost = false;
  let postContent = '';
  let postType = 'post';
  let isAnonymous = false;
  let isSubmitting = false;
  
  function exitWall() {
    currentView.set('home');
  }
  
  function openCreatePost() {
    showCreatePost = true;
    postContent = '';
    postType = 'post';
    isAnonymous = false;
  }
  
  function closeCreatePost() {
    showCreatePost = false;
    postContent = '';
    postType = 'post';
    isAnonymous = false;
  }
  
  async function submitPost() {
    if (!postContent.trim() || isSubmitting) return;
    
    isSubmitting = true;
    const user = await authStore.getUser();
    
    if (!user) {
      alert('Please log in to post');
      isSubmitting = false;
      return;
    }
    
    try {
      const { error } = await supabase
        .from('community_posts')
        .insert({
          user_id: user.id,
          user_name: user.user_metadata?.name || 'Anonymous',
          content: postContent.trim(),
          share_type: postType,
          is_anonymous: isAnonymous,
          is_fellowship_only: false // Explicitly mark as community post
        });
      
      if (error) throw error;
      
      // Success - close modal and reset
      closeCreatePost();
    } catch (error) {
      console.error('Error posting:', error);
      alert('Failed to create post. Please try again.');
    } finally {
      isSubmitting = false;
    }
  }
  
  // Different note colors for variety
  const noteColors = [
    '#fffacd', // Light yellow
    '#ffE4e1', // Misty rose
    '#e0ffff', // Light cyan
    '#f0fff0', // Honeydew
    '#fff0f5', // Lavender blush
    '#f5fffa', // Mint cream
    '#ffefd5', // Papaya whip
    '#ffe4b5', // Moccasin
  ];
  
  // Pin styles for variety
  const pinTypes = ['📌', '📍', '🔖', '📎'];
  
  onMount(async () => {
    await loadWallNotes();
    setupRealtimeSubscription();
  });
  
  async function loadWallNotes() {
    loading = true;
    
    // Load shared journal entries from community_posts (exclude fellowship-only posts)
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
      .or('is_fellowship_only.is.null,is_fellowship_only.eq.false')
      .order('created_at', { ascending: false })
      .limit(50);
    
    if (!error && data) {
      // Process notes with random positioning and styling
      wallNotes = data.map((post, index) => ({
        ...post,
        noteColor: noteColors[Math.floor(Math.random() * noteColors.length)],
        pinType: pinTypes[Math.floor(Math.random() * pinTypes.length)],
        rotation: Math.random() * 10 - 5, // -5 to 5 degrees
        xOffset: Math.random() * 20 - 10, // -10 to 10 px
        yOffset: Math.random() * 20 - 10, // -10 to 10 px
        zIndex: Math.floor(Math.random() * 10),
      }));
    }
    
    loading = false;
  }
  
  function setupRealtimeSubscription() {
    supabase
      .channel('community-wall')
      .on('postgres_changes', 
        { event: 'INSERT', schema: 'public', table: 'community_posts' },
        (payload) => {
          const newNote = {
            ...payload.new,
            noteColor: noteColors[Math.floor(Math.random() * noteColors.length)],
            pinType: pinTypes[Math.floor(Math.random() * pinTypes.length)],
            rotation: Math.random() * 10 - 5,
            xOffset: Math.random() * 20 - 10,
            yOffset: Math.random() * 20 - 10,
            zIndex: Math.floor(Math.random() * 10),
            reactions: [],
            encouragements: []
          };
          wallNotes = [newNote, ...wallNotes];
        }
      )
      .subscribe();
  }
  
  function viewNoteDetail(note: any) {
    selectedNote = note;
    showNoteDetail = true;
  }
  
  function closeNoteDetail() {
    selectedNote = null;
    showNoteDetail = false;
  }
  
  async function addPrayer(noteId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    const note = wallNotes.find(n => n.id === noteId);
    if (!note) return;
    
    // Toggle prayer reaction
    const existingReaction = note.reactions?.find(
      r => r.reaction === 'pray' && r.user_id === user.id
    );
    
    if (existingReaction) {
      // Remove prayer
      await supabase
        .from('reactions')
        .delete()
        .eq('id', existingReaction.id);
      
      note.reactions = note.reactions.filter(r => r.id !== existingReaction.id);
    } else {
      // Add prayer
      const { data } = await supabase
        .from('reactions')
        .insert({
          post_id: noteId,
          user_id: user.id,
          reaction: 'pray'
        })
        .select()
        .single();
      
      if (data) {
        if (!note.reactions) note.reactions = [];
        note.reactions.push(data);
      }
    }
    
    wallNotes = wallNotes;
  }
  
  function formatDate(dateString: string) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) {
      const hours = Math.floor(diff / (1000 * 60 * 60));
      if (hours === 0) {
        const minutes = Math.floor(diff / (1000 * 60));
        return `${minutes}m ago`;
      }
      return `${hours}h ago`;
    }
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days}d ago`;
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }
  
  function truncateText(text: string, maxLength: number = 100) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength).trim() + '...';
  }
</script>

<div class="wall-container fullscreen">
  <div class="wall-header">
    <button class="exit-wall-btn" on:click={exitWall}>
      ← Back
    </button>
    <h1>✨ Community Wall ✨</h1>
    <p class="wall-subtitle">Shared journal entries, prayers, and testimonies from the faithful</p>
    <button class="create-post-btn" on:click={openCreatePost}>
      <span class="desktop-text">✍️ Pin a Note</span>
      <span class="mobile-text">✍️</span>
    </button>
  </div>
  
  {#if loading}
    <div class="loading">Loading prayer wall...</div>
  {:else}
    <div class="bulletin-board">
      <div class="wood-texture"></div>
      
      <div class="notes-grid">
        {#each wallNotes as note}
          <div 
            class="wall-note"
            style="
              background: {note.noteColor};
              transform: rotate({note.rotation}deg) translate({note.xOffset}px, {note.yOffset}px);
              z-index: {note.zIndex};
            "
            on:click={() => viewNoteDetail(note)}
            role="button"
            tabindex="0"
          >
            <div class="pin">{note.pinType}</div>
            
            <div class="note-content">
              {#if note.share_type === 'prayer'}
                <div class="note-type prayer">🙏 Prayer Request</div>
              {:else if note.share_type === 'testimony'}
                <div class="note-type testimony">✨ Testimony</div>
              {:else if note.share_type === 'praise'}
                <div class="note-type praise">🎉 Praise</div>
              {/if}
              
              <p class="note-text">
                {truncateText(note.content, 120)}
              </p>
              
              <div class="note-footer">
                <span class="note-author">
                  {note.is_anonymous ? 'Anonymous' : note.user_name}
                </span>
                <span class="note-date">{formatDate(note.created_at)}</span>
              </div>
              
              {#if note.reactions?.filter(r => r.reaction === 'pray').length > 0}
                <div class="prayer-count">
                  🙏 {note.reactions.filter(r => r.reaction === 'pray').length}
                </div>
              {/if}
            </div>
          </div>
        {/each}
      </div>
      
      {#if wallNotes.length === 0}
        <div class="empty-wall">
          <p>The prayer wall is empty.</p>
          <p>Click "Pin a Note" to add the first post!</p>
        </div>
      {/if}
    </div>
  {/if}
  
  <!-- Note Detail Modal -->
  {#if showNoteDetail && selectedNote}
    <div class="note-detail-overlay" on:click={closeNoteDetail}>
      <div class="note-detail" on:click|stopPropagation>
        <button class="close-btn" on:click={closeNoteDetail}>✕</button>
        
        <div class="detail-header">
          {#if selectedNote.share_type === 'prayer'}
            <span class="detail-type prayer">🙏 Prayer Request</span>
          {:else if selectedNote.share_type === 'testimony'}
            <span class="detail-type testimony">✨ Testimony</span>
          {:else if selectedNote.share_type === 'praise'}
            <span class="detail-type praise">🎉 Praise Report</span>
          {/if}
        </div>
        
        <div class="detail-content">
          {selectedNote.content}
        </div>
        
        <div class="detail-footer">
          <div class="detail-author">
            {selectedNote.is_anonymous ? 'Anonymous' : selectedNote.user_name}
            {#if !selectedNote.is_anonymous && selectedNote.user_id !== $authStore?.id}
              <button 
                class="chat-btn"
                on:click={() => {
                  if (typeof window !== 'undefined' && (window as any).openPrivateChat) {
                    (window as any).openPrivateChat(selectedNote.user_id, selectedNote.user_name);
                  }
                }}
                title="Start private chat"
              >
                💬
              </button>
            {/if}
          </div>
          <div class="detail-date">
            {new Date(selectedNote.created_at).toLocaleString()}
          </div>
        </div>
        
        <div class="detail-actions">
          <button 
            class="prayer-btn"
            class:active={selectedNote.reactions?.some(r => 
              r.reaction === 'pray' && r.user_id === $authStore?.id
            )}
            on:click={() => addPrayer(selectedNote.id)}
          >
            🙏 Pray for this
            {#if selectedNote.reactions?.filter(r => r.reaction === 'pray').length > 0}
              ({selectedNote.reactions.filter(r => r.reaction === 'pray').length})
            {/if}
          </button>
          
          {#if selectedNote.encouragements?.length > 0}
            <div class="encouragements">
              <h4>Encouragements:</h4>
              {#each selectedNote.encouragements as encouragement}
                <div class="encouragement">
                  <strong>{encouragement.user_name}:</strong> {encouragement.message}
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    </div>
  {/if}
  
  <!-- Create Post Modal -->
  {#if showCreatePost}
    <div class="create-post-overlay" on:click={closeCreatePost}>
      <div class="create-post-modal" on:click|stopPropagation>
        <button class="close-btn" on:click={closeCreatePost}>✕</button>
        
        <h2>📝 Pin a Note to the Wall</h2>
        
        <div class="post-form">
          <div class="form-group">
            <label for="post-type">Type of Post:</label>
            <select id="post-type" bind:value={postType} class="post-type-select">
              <option value="post">General</option>
              <option value="prayer">🙏 Prayer Request</option>
              <option value="testimony">✨ Testimony</option>
              <option value="praise">🎉 Praise Report</option>
            </select>
          </div>
          
          <div class="form-group">
            <label for="post-content">Your Message:</label>
            <textarea 
              id="post-content"
              bind:value={postContent}
              placeholder={postType === 'prayer' ? 'Share your prayer request...' : 
                          postType === 'testimony' ? 'Share your testimony...' :
                          postType === 'praise' ? 'Share your praise report...' :
                          'Share your thoughts...'}
              class="post-textarea"
              rows="6"
              maxlength="500"
            ></textarea>
            <div class="char-count">{postContent.length}/500</div>
          </div>
          
          <div class="form-group checkbox-group">
            <label class="checkbox-label">
              <input type="checkbox" bind:checked={isAnonymous} />
              <span>Post anonymously</span>
            </label>
          </div>
          
          <div class="form-actions">
            <button 
              class="cancel-btn" 
              on:click={closeCreatePost}
              disabled={isSubmitting}
            >
              Cancel
            </button>
            <button 
              class="submit-btn"
              on:click={submitPost}
              disabled={!postContent.trim() || isSubmitting}
            >
              {isSubmitting ? 'Pinning...' : '📌 Pin to Wall'}
            </button>
          </div>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  /* Add handwriting font from Google Fonts */
  @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@400;600&display=swap');
  
  .wall-container {
    min-height: calc(100vh - 200px);
    padding: 1rem;
  }
  
  .wall-container.fullscreen {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    min-height: 100vh;
    width: 100vw;
    z-index: 999;
    /* Realistic corkboard texture */
    background: 
      /* Subtle grain overlay */
      repeating-linear-gradient(
        90deg,
        rgba(139, 90, 43, 0.1) 0px,
        transparent 1px,
        transparent 2px,
        rgba(139, 90, 43, 0.1) 3px
      ),
      repeating-linear-gradient(
        0deg,
        rgba(160, 82, 45, 0.1) 0px,
        transparent 1px,
        transparent 2px,
        rgba(160, 82, 45, 0.1) 3px
      ),
      /* Cork texture gradients */
      radial-gradient(ellipse at 20% 30%, #c8986b 0%, transparent 50%),
      radial-gradient(ellipse at 60% 70%, #daa76a 0%, transparent 50%),
      radial-gradient(ellipse at 80% 20%, #d4a574 0%, transparent 40%),
      radial-gradient(ellipse at 40% 80%, #c8986b 0%, transparent 50%),
      /* Base cork color */
      linear-gradient(180deg, #d4a574 0%, #c8986b 50%, #b8935f 100%);
    background-size: 4px 4px, 4px 4px, 300px 300px, 400px 400px, 350px 350px, 450px 450px, 100% 100%;
    overflow-y: auto;
    padding: 0;
    /* Inner shadow for depth */
    box-shadow: 
      inset 0 0 100px rgba(0, 0, 0, 0.2),
      inset 0 0 50px rgba(101, 67, 33, 0.3),
      inset 0 0 30px rgba(139, 90, 43, 0.2);
  }
  
  /* Wood frame effect overlay */
  .wall-container.fullscreen::before {
    content: '';
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    pointer-events: none;
    z-index: 1000;
    /* Wood frame border shadow */
    box-shadow: 
      inset 0 0 60px rgba(0, 0, 0, 0.6),
      inset 0 0 30px rgba(92, 51, 23, 0.5),
      inset 5px 5px 20px rgba(0, 0, 0, 0.4),
      inset -5px -5px 20px rgba(0, 0, 0, 0.4);
  }
  
  .fullscreen .wall-header {
    text-align: center;
    margin-bottom: 1rem;
    padding: 1rem;
    background: linear-gradient(180deg, rgba(92, 51, 23, 0.95) 0%, rgba(139, 90, 43, 0.8) 50%, transparent 100%);
    position: sticky;
    top: 0;
    z-index: 1001;
    backdrop-filter: blur(5px);
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
  }
  
  .exit-wall-btn {
    position: absolute;
    top: 1rem;
    left: 1rem;
    padding: 0.5rem 1rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    color: var(--text-divine);
    border-radius: 20px;
    cursor: pointer;
    font-size: 0.9rem;
    transition: all 0.3s;
    z-index: 101;
  }
  
  .exit-wall-btn:hover {
    background: rgba(255, 215, 0, 0.2);
    transform: translateX(-5px);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .create-post-btn {
    position: absolute;
    top: 1rem;
    right: 1rem;
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, #ffd700, #ffed4e);
    border: 2px solid var(--border-gold);
    color: #333;
    border-radius: 25px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 600;
    transition: all 0.3s;
    z-index: 101;
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
  }
  
  .create-post-btn:hover {
    background: linear-gradient(135deg, #ffed4e, #ffd700);
    transform: translateY(-2px);
    box-shadow: 0 6px 25px rgba(255, 215, 0, 0.4);
  }
  
  .desktop-text {
    display: inline;
  }
  
  .mobile-text {
    display: none;
  }
  
  .wall-header {
    text-align: center;
    margin-bottom: 2rem;
  }
  
  .wall-header h1 {
    color: #fff;
    font-size: 2.8rem;
    margin: 0;
    text-shadow: 
      3px 3px 6px rgba(0, 0, 0, 0.9),
      0 0 20px rgba(255, 215, 0, 0.4);
    font-family: 'Caveat', cursive;
    font-weight: 700;
    letter-spacing: 3px;
  }
  
  .wall-subtitle {
    color: var(--text-scripture);
    margin: 0.5rem 0;
    font-style: italic;
  }
  
  .bulletin-board {
    position: relative;
    background: linear-gradient(135deg, #8B4513, #A0522D);
    border: 12px solid #654321;
    border-radius: 8px;
    box-shadow: 
      inset 0 0 50px rgba(0, 0, 0, 0.5),
      0 10px 40px rgba(0, 0, 0, 0.7);
    min-height: 600px;
    padding: 2rem;
    overflow: hidden;
  }
  
  .fullscreen .bulletin-board {
    border-radius: 0;
    border: none;
    min-height: 100vh;
    padding: 1rem;
    margin: 0;
  }
  
  .wood-texture {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    opacity: 0.3;
    background-image: 
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 2px,
        rgba(0, 0, 0, 0.1) 2px,
        rgba(0, 0, 0, 0.1) 4px
      );
    pointer-events: none;
  }
  
  .notes-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 1.5rem;
    position: relative;
  }
  
  .fullscreen .notes-grid {
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 2rem;
    padding: 1rem;
    max-width: 1800px;
    margin: 0 auto;
  }
  
  .wall-note {
    position: relative;
    padding: 1rem;
    min-height: 180px;
    cursor: pointer;
    transition: all 0.3s;
    /* Realistic layered paper shadow */
    box-shadow: 
      0 1px 1px rgba(0, 0, 0, 0.15),
      0 3px 3px rgba(0, 0, 0, 0.15),
      0 6px 6px rgba(0, 0, 0, 0.15),
      0 10px 10px rgba(0, 0, 0, 0.15),
      0 15px 15px rgba(0, 0, 0, 0.15);
    font-family: 'Caveat', cursive, var(--font-secondary);
    color: #333;
    /* Paper texture with lines */
    background-image: 
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 28px,
        rgba(0, 82, 204, 0.05) 28px,
        rgba(0, 82, 204, 0.05) 29px
      ),
      radial-gradient(
        ellipse at 50% 50%,
        rgba(255, 255, 255, 0.9) 0%,
        transparent 70%
      );
    /* Slightly folded corner */
    border-radius: 0 0 0 3px;
  }
  
  /* Paper fold effect at bottom corner */
  .wall-note::after {
    content: '';
    position: absolute;
    bottom: 0;
    right: 0;
    width: 25px;
    height: 25px;
    background: linear-gradient(
      -45deg,
      rgba(0, 0, 0, 0.08) 45%,
      transparent 50%
    );
    border-radius: 0 0 0 100%;
  }
  
  .wall-note:hover {
    transform: scale(1.08) rotate(0deg) !important;
    z-index: 100 !important;
    box-shadow: 
      0 2px 2px rgba(0, 0, 0, 0.2),
      0 6px 6px rgba(0, 0, 0, 0.2),
      0 12px 12px rgba(0, 0, 0, 0.2),
      0 20px 20px rgba(0, 0, 0, 0.2),
      0 30px 30px rgba(0, 0, 0, 0.2);
  }
  
  .pin {
    position: absolute;
    top: -10px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 1.8rem;
    /* Realistic pushpin shadow */
    filter: 
      drop-shadow(0 2px 2px rgba(0, 0, 0, 0.4))
      drop-shadow(0 3px 4px rgba(0, 0, 0, 0.2));
    z-index: 1;
    /* Slight rotation for realism */
    transform: translateX(-50%) rotate(5deg);
  }
  
  .note-content {
    margin-top: 0.5rem;
  }
  
  .note-type {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    border-radius: 10px;
    font-size: 0.75rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
    font-family: var(--font-secondary);
  }
  
  .note-type.prayer {
    background: rgba(138, 43, 226, 0.2);
    color: #6a1b9a;
  }
  
  .note-type.testimony {
    background: rgba(255, 193, 7, 0.2);
    color: #f57c00;
  }
  
  .note-type.praise {
    background: rgba(76, 175, 80, 0.2);
    color: #2e7d32;
  }
  
  .note-text {
    font-size: 0.95rem;
    line-height: 1.4;
    margin: 0.5rem 0;
    word-wrap: break-word;
  }
  
  .note-footer {
    position: absolute;
    bottom: 0.5rem;
    left: 1rem;
    right: 1rem;
    display: flex;
    justify-content: space-between;
    font-size: 0.7rem;
    opacity: 0.7;
    font-family: var(--font-secondary);
  }
  
  .note-author {
    font-weight: 600;
  }
  
  .prayer-count {
    position: absolute;
    bottom: 0.5rem;
    right: 0.5rem;
    background: rgba(255, 255, 255, 0.9);
    padding: 0.15rem 0.4rem;
    border-radius: 10px;
    font-size: 0.7rem;
    font-family: var(--font-secondary);
  }
  
  .empty-wall {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    text-align: center;
    color: rgba(255, 255, 255, 0.7);
    font-size: 1.2rem;
  }
  
  /* Note Detail Modal */
  .note-detail-overlay {
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
    padding: 1rem;
  }
  
  .note-detail {
    background: #fffacd;
    color: #333;
    max-width: 600px;
    width: 100%;
    max-height: 80vh;
    overflow-y: auto;
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
    position: relative;
    font-family: 'Caveat', cursive, var(--font-secondary);
    font-size: 1.1rem;
  }
  
  .close-btn {
    position: absolute;
    top: 1rem;
    right: 1rem;
    background: none;
    border: none;
    font-size: 1.5rem;
    cursor: pointer;
    color: #666;
    transition: all 0.2s;
  }
  
  .close-btn:hover {
    transform: scale(1.2);
    color: #333;
  }
  
  .detail-header {
    margin-bottom: 1rem;
  }
  
  .detail-type {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 15px;
    font-size: 0.9rem;
    font-weight: 600;
    font-family: var(--font-secondary);
  }
  
  .detail-content {
    line-height: 1.6;
    margin: 1.5rem 0;
    white-space: pre-wrap;
  }
  
  .detail-footer {
    border-top: 1px solid rgba(0, 0, 0, 0.1);
    padding-top: 1rem;
    margin-top: 1rem;
    display: flex;
    justify-content: space-between;
    font-size: 0.9rem;
    opacity: 0.7;
    font-family: var(--font-secondary);
  }
  
  .detail-author {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .detail-author .chat-btn {
    padding: 0.25rem 0.5rem;
    background: rgba(138, 43, 226, 0.2);
    color: var(--text-divine);
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 6px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
    opacity: 1;
  }
  
  .detail-author .chat-btn:hover {
    background: rgba(138, 43, 226, 0.3);
    transform: scale(1.05);
    box-shadow: 0 0 10px rgba(138, 43, 226, 0.4);
  }
  
  .detail-actions {
    margin-top: 1.5rem;
  }
  
  .prayer-btn {
    padding: 0.5rem 1.5rem;
    background: linear-gradient(135deg, #8a2be2, #4b0082);
    color: white;
    border: none;
    border-radius: 20px;
    cursor: pointer;
    font-size: 1rem;
    transition: all 0.3s;
    font-family: var(--font-secondary);
  }
  
  .prayer-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(138, 43, 226, 0.3);
  }
  
  .prayer-btn.active {
    background: linear-gradient(135deg, #4b0082, #8a2be2);
  }
  
  .encouragements {
    margin-top: 1.5rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(0, 0, 0, 0.1);
  }
  
  .encouragements h4 {
    margin: 0 0 0.5rem 0;
    font-family: var(--font-secondary);
  }
  
  .encouragement {
    padding: 0.5rem;
    background: rgba(255, 255, 255, 0.5);
    border-radius: 6px;
    margin-bottom: 0.5rem;
    font-size: 0.9rem;
    font-family: var(--font-secondary);
  }
  
  .loading {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  /* Create Post Modal Styles */
  .create-post-overlay {
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
    padding: 1rem;
  }
  
  .create-post-modal {
    background: linear-gradient(135deg, #1a1a2e, #0f0f1e);
    border: 2px solid var(--border-gold);
    color: var(--text-divine);
    max-width: 500px;
    width: 100%;
    max-height: 80vh;
    overflow-y: auto;
    padding: 2rem;
    border-radius: 15px;
    box-shadow: 
      0 20px 60px rgba(0, 0, 0, 0.8),
      0 0 40px rgba(255, 215, 0, 0.2);
    position: relative;
  }
  
  .create-post-modal h2 {
    color: var(--text-divine);
    margin: 0 0 1.5rem 0;
    text-align: center;
    font-size: 1.8rem;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .post-form {
    display: flex;
    flex-direction: column;
    gap: 1.2rem;
  }
  
  .form-group {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .form-group label {
    color: var(--text-scripture);
    font-size: 0.9rem;
    font-weight: 600;
  }
  
  .post-type-select {
    padding: 0.75rem;
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    color: var(--text-divine);
    font-size: 1rem;
    transition: all 0.3s;
  }
  
  .post-type-select:focus {
    outline: none;
    border-color: var(--text-divine);
    background: rgba(255, 215, 0, 0.1);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .post-type-select option {
    background: #1a1a2e;
    color: var(--text-divine);
  }
  
  .post-textarea {
    padding: 1rem;
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    color: var(--text-divine);
    font-size: 1rem;
    font-family: inherit;
    resize: vertical;
    min-height: 120px;
    transition: all 0.3s;
  }
  
  .post-textarea:focus {
    outline: none;
    border-color: var(--text-divine);
    background: rgba(255, 215, 0, 0.1);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .post-textarea::placeholder {
    color: rgba(255, 215, 0, 0.4);
  }
  
  .char-count {
    text-align: right;
    font-size: 0.8rem;
    color: var(--text-scripture);
    margin-top: -0.3rem;
  }
  
  .checkbox-group {
    margin: 0.5rem 0;
  }
  
  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    color: var(--text-scripture);
    font-size: 0.95rem;
  }
  
  .checkbox-label input[type="checkbox"] {
    width: 18px;
    height: 18px;
    accent-color: var(--text-divine);
    cursor: pointer;
  }
  
  .form-actions {
    display: flex;
    gap: 1rem;
    justify-content: flex-end;
    margin-top: 1rem;
  }
  
  .cancel-btn {
    padding: 0.75rem 1.5rem;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    color: var(--text-scripture);
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    transition: all 0.3s;
  }
  
  .cancel-btn:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.15);
    border-color: rgba(255, 255, 255, 0.3);
  }
  
  .submit-btn {
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, #ffd700, #ffed4e);
    border: none;
    color: #333;
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 600;
    transition: all 0.3s;
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
  }
  
  .submit-btn:hover:not(:disabled) {
    background: linear-gradient(135deg, #ffed4e, #ffd700);
    transform: translateY(-2px);
    box-shadow: 0 6px 25px rgba(255, 215, 0, 0.4);
  }
  
  .submit-btn:disabled,
  .cancel-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  
  @media (max-width: 768px) {
    .notes-grid {
      grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
      gap: 1rem;
    }
    
    .wall-note {
      min-height: 150px;
      padding: 0.75rem;
    }
    
    .note-text {
      font-size: 0.85rem;
    }
    
    .create-post-btn {
      position: fixed;
      bottom: 2rem;
      right: 1rem;
      top: auto;
      padding: 1rem;
      width: 60px;
      height: 60px;
      border-radius: 50%;
      font-size: 1.5rem;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 20px rgba(255, 215, 0, 0.4);
    }
    
    .create-post-btn:hover {
      transform: scale(1.1);
    }
    
    .desktop-text {
      display: none;
    }
    
    .mobile-text {
      display: inline;
    }
    
    .create-post-modal {
      padding: 1.5rem;
      margin: 1rem;
    }
    
    .wall-header h1 {
      font-size: 2rem;
    }
  }
</style>