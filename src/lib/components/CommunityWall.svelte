<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  let wallNotes: any[] = [];
  let loading = true;
  let selectedNote: any = null;
  let showNoteDetail = false;
  
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
    
    // Load shared journal entries from community_posts
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

<div class="wall-container">
  <div class="wall-header">
    <h1>🏛️ Community Prayer Wall</h1>
    <p class="wall-subtitle">Shared journal entries, prayers, and testimonies from the faithful</p>
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
          <p>Share a journal entry to pin the first note!</p>
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
</div>

<style>
  .wall-container {
    min-height: calc(100vh - 200px);
    padding: 1rem;
  }
  
  .wall-header {
    text-align: center;
    margin-bottom: 2rem;
  }
  
  .wall-header h1 {
    color: var(--text-divine);
    font-size: 2.5rem;
    margin: 0;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
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
  
  .wall-note {
    position: relative;
    padding: 1rem;
    min-height: 180px;
    cursor: pointer;
    transition: all 0.3s;
    box-shadow: 
      2px 2px 10px rgba(0, 0, 0, 0.3),
      inset 0 0 20px rgba(0, 0, 0, 0.05);
    font-family: 'Caveat', cursive, var(--font-secondary);
    color: #333;
    background-image: 
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 20px,
        rgba(0, 0, 0, 0.02) 20px,
        rgba(0, 0, 0, 0.02) 21px
      );
  }
  
  .wall-note:hover {
    transform: scale(1.05) rotate(0deg) !important;
    z-index: 100 !important;
    box-shadow: 
      4px 4px 20px rgba(0, 0, 0, 0.4),
      0 0 30px rgba(255, 215, 0, 0.2);
  }
  
  .pin {
    position: absolute;
    top: -10px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 1.5rem;
    filter: drop-shadow(2px 2px 4px rgba(0, 0, 0, 0.3));
    z-index: 1;
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
  
  /* Add handwriting font from Google Fonts */
  @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@400;600&display=swap');
  
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
  }
</style>