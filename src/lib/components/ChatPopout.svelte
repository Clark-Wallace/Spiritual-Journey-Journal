<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  export let recipientId: string;
  export let recipientName: string;
  export let onClose: () => void;
  export let zIndex: number = 1000;
  export let initialPosition = { x: 100, y: 100 };
  
  let messages: any[] = [];
  let newMessage = '';
  let loading = false;
  let messagesContainer: HTMLDivElement;
  let subscription: any;
  let presenceSubscription: any;
  let otherUserPresent = true;
  let presenceTimeoutId: any;
  let presenceCheckTimeout: any;
  let hasShownJoinedMessage = false;
  
  // Window state
  let isMinimized = false;
  let isDragging = false;
  let isResizing = false;
  let dragStart = { x: 0, y: 0 };
  let position = { ...initialPosition };
  let size = { width: 350, height: 450 };
  let resizeStart = { width: 350, height: 450, x: 0, y: 0 };
  let windowElement: HTMLDivElement;
  
  onMount(() => {
    loadMessages();
    setupRealtimeSubscription();
    setupChatPresence();
  });
  
  onDestroy(() => {
    if (subscription) {
      subscription.unsubscribe();
    }
    if (presenceSubscription) {
      try {
        presenceSubscription.untrack();
        presenceSubscription.unsubscribe();
      } catch (e) {
        console.warn('Error cleaning up presence:', e);
      }
    }
    if (presenceTimeoutId) {
      clearTimeout(presenceTimeoutId);
    }
    if (presenceCheckTimeout) {
      clearTimeout(presenceCheckTimeout);
    }
  });
  
  async function loadMessages() {
    loading = true;
    const user = await getCurrentUser();
    if (!user) return;
    
    // Try RPC function first, fallback to direct query
    let { data, error } = await supabase
      .rpc('get_conversation_messages', {
        p_user_id: user.id,
        p_other_user_id: recipientId,
        p_limit: 50,
        p_offset: 0
      });
    
    if (error && (error.message?.includes('function') || error?.code === '42883' || error?.code === '42702')) {
      const result = await supabase
        .from('private_messages')
        .select('*')
        .or(`and(from_user_id.eq.${user.id},to_user_id.eq.${recipientId}),and(from_user_id.eq.${recipientId},to_user_id.eq.${user.id})`)
        .order('created_at', { ascending: false })
        .limit(50);
      
      if (!result.error && result.data) {
        data = result.data.map(msg => ({
          message_id: msg.id,
          from_user_id: msg.from_user_id,
          from_user_name: msg.from_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
          to_user_id: msg.to_user_id,
          to_user_name: msg.to_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
          message: msg.message,
          is_read: msg.is_read,
          created_at: msg.created_at,
          is_mine: msg.from_user_id === user.id
        })).reverse();
        
        await supabase
          .from('private_messages')
          .update({ is_read: true })
          .eq('to_user_id', user.id)
          .eq('from_user_id', recipientId)
          .eq('is_read', false);
      }
    } else if (data) {
      data = data.reverse();
    }
    
    if (data) {
      messages = data;
      scrollToBottom();
    }
    
    loading = false;
  }
  
  async function sendMessage() {
    if (!newMessage.trim()) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('private_messages')
      .insert({
        from_user_id: user.id,
        to_user_id: recipientId,
        message: newMessage.trim()
      });
    
    if (!error) {
      newMessage = '';
    }
  }
  
  function setupRealtimeSubscription() {
    const user = $authStore;
    if (!user) return;
    
    subscription = supabase
      .channel(`private-msg-${user.id}-${recipientId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'private_messages'
      }, (payload) => {
        const msg = payload.new;
        if ((msg.from_user_id === user.id && msg.to_user_id === recipientId) ||
            (msg.from_user_id === recipientId && msg.to_user_id === user.id)) {
          
          messages = [...messages, {
            message_id: msg.id,
            from_user_id: msg.from_user_id,
            from_user_name: msg.from_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
            to_user_id: msg.to_user_id,
            to_user_name: msg.to_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
            message: msg.message,
            is_read: msg.is_read,
            created_at: msg.created_at,
            is_mine: msg.from_user_id === user.id
          }];
          
          scrollToBottom();
          
          if (msg.to_user_id === user.id && !msg.is_read) {
            markAsRead(msg.id);
          }
          
          // Flash window if minimized
          if (isMinimized) {
            flashWindow();
          }
        }
      })
      .subscribe();
  }
  
  async function setupChatPresence() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const conversationId = [user.id, recipientId].sort().join('-');
    
    presenceSubscription = supabase
      .channel(`chat-presence-${conversationId}`)
      .on('presence', { event: 'sync' }, () => {
        if (!presenceSubscription) return;
        const state = presenceSubscription.presenceState();
        const wasPresent = otherUserPresent;
        otherUserPresent = Object.keys(state).some(key => {
          const presence = state[key][0];
          return presence && presence.user_id === recipientId;
        });
        
        if (!wasPresent && otherUserPresent) {
          hasShownJoinedMessage = true;
        }
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await presenceSubscription.track({
            user_id: user.id,
            conversation_id: conversationId,
            online_at: new Date().toISOString(),
          });
        }
      });
  }
  
  async function markAsRead(messageId: string) {
    await supabase
      .from('private_messages')
      .update({ is_read: true })
      .eq('id', messageId);
  }
  
  function scrollToBottom() {
    setTimeout(() => {
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }, 100);
  }
  
  function formatTime(timestamp: string) {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) {
      return date.toLocaleTimeString('en-US', { 
        hour: 'numeric', 
        minute: '2-digit',
        hour12: true 
      });
    } else if (days === 1) {
      return 'Yesterday';
    } else if (days < 7) {
      return date.toLocaleDateString('en-US', { weekday: 'short' });
    } else {
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    }
  }
  
  // Window management
  function startDrag(e: MouseEvent | TouchEvent) {
    if (isResizing) return; // Only prevent dragging when resizing, not when minimized
    isDragging = true;
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;
    dragStart = {
      x: clientX - position.x,
      y: clientY - position.y
    };
    e.preventDefault();
    // Prevent text selection while dragging
    document.body.style.userSelect = 'none';
  }
  
  function onMouseMove(e: MouseEvent | TouchEvent) {
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;
    
    if (isDragging) {
      position = {
        x: Math.max(0, Math.min(window.innerWidth - size.width, clientX - dragStart.x)),
        y: Math.max(0, Math.min(window.innerHeight - 50, clientY - dragStart.y))
      };
    } else if (isResizing) {
      size = {
        width: Math.max(250, Math.min(800, resizeStart.width + (clientX - resizeStart.x))),
        height: Math.max(300, Math.min(700, resizeStart.height + (clientY - resizeStart.y)))
      };
    }
  }
  
  function onMouseUp() {
    isDragging = false;
    isResizing = false;
    document.body.style.userSelect = '';
  }
  
  function startResize(e: MouseEvent) {
    isResizing = true;
    resizeStart = {
      width: size.width,
      height: size.height,
      x: e.clientX,
      y: e.clientY
    };
    e.preventDefault();
    e.stopPropagation();
    document.body.style.userSelect = 'none';
  }
  
  function toggleMinimize() {
    isMinimized = !isMinimized;
  }
  
  function flashWindow() {
    if (windowElement) {
      windowElement.classList.add('flash');
      setTimeout(() => {
        windowElement?.classList.remove('flash');
      }, 1000);
    }
  }
  
  function bringToFront() {
    // Parent component should handle z-index management
    windowElement?.focus();
  }
  
  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  }
</script>

<svelte:window 
  on:mousemove={onMouseMove}
  on:mouseup={onMouseUp}
  on:touchmove={onMouseMove}
  on:touchend={onMouseUp}
/>

{@const isMobile = typeof window !== 'undefined' && window.innerWidth <= 768}

<div 
  class="chat-popout"
  class:minimized={isMinimized}
  class:dragging={isDragging}
  class:resizing={isResizing}
  class:mobile={isMobile}
  style="{isMobile && !isDragging ? '' : `left: ${position.x}px; top: ${position.y}px;`} z-index: {zIndex}; width: {size.width}px; height: {isMinimized ? 'auto' : size.height + 'px'}"
  bind:this={windowElement}
  on:mousedown={bringToFront}
  role="dialog"
  aria-label="Chat with {recipientName}"
>
  <div 
    class="chat-header"
    on:mousedown={startDrag}
    on:touchstart={startDrag}
  >
    <div class="header-info">
      <span class="chat-icon">💬</span>
      <span class="chat-title">{recipientName}</span>
      <span class="presence-dot {otherUserPresent ? 'online' : 'offline'}"></span>
    </div>
    <div class="header-controls">
      <button 
        class="control-btn minimize"
        on:click={toggleMinimize}
        title={isMinimized ? 'Restore' : 'Minimize'}
      >
        {isMinimized ? '▢' : '—'}
      </button>
      <button 
        class="control-btn close"
        on:click={onClose}
        title="Close chat"
      >
        ✕
      </button>
    </div>
  </div>
  
  {#if !isMinimized}
    <div class="chat-body">
      <div class="messages-container" bind:this={messagesContainer}>
        {#if loading}
          <div class="loading">Loading messages...</div>
        {:else if messages.length === 0}
          <div class="no-messages">
            <p>No messages yet</p>
            <p>Say hello to start the conversation!</p>
          </div>
        {:else}
          {#each messages as message}
            <div class="message {message.is_mine ? 'mine' : 'theirs'}">
              <div class="message-bubble">
                <div class="message-text">{message.message}</div>
                <div class="message-time">{formatTime(message.created_at)}</div>
              </div>
            </div>
          {/each}
        {/if}
      </div>
      
      <div class="chat-input">
        <input
          type="text"
          bind:value={newMessage}
          placeholder="Type a message..."
          on:keydown={handleKeydown}
          class="message-input"
        />
        <button 
          class="send-btn"
          on:click={sendMessage}
          disabled={!newMessage.trim()}
        >
          Send
        </button>
      </div>
    </div>
  {/if}
  
  <!-- Resize handle - only show when not minimized -->
  {#if !isMinimized}
    <div 
      class="resize-handle"
      on:mousedown={startResize}
      title="Drag to resize"
    ></div>
  {/if}
</div>

<style>
  .chat-popout {
    position: fixed;
    background: linear-gradient(135deg, #1a1a2e, #0f0f1e);
    border: 2px solid var(--border-gold);
    border-radius: 12px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.8),
                0 0 20px rgba(255, 215, 0, 0.2);
    display: flex;
    flex-direction: column;
    transition: transform 0.3s ease;
    min-width: 250px;
    min-height: 300px;
  }
  
  .chat-popout.minimized {
    height: auto !important;
    min-height: auto !important;
  }
  
  .chat-popout.minimized .chat-header {
    border-radius: 10px;
    border-bottom: none;
  }
  
  .chat-popout.dragging, .chat-popout.resizing {
    transition: none;
    opacity: 0.9;
    cursor: move;
  }
  
  .chat-popout.resizing {
    cursor: nwse-resize;
  }
  
  .chat-popout.flash {
    animation: flash-animation 0.5s ease 2;
  }
  
  @keyframes flash-animation {
    0%, 100% { 
      transform: scale(1);
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.8),
                  0 0 20px rgba(255, 215, 0, 0.2);
    }
    50% { 
      transform: scale(1.02);
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.8),
                  0 0 40px rgba(255, 215, 0, 0.5);
    }
  }
  
  .chat-header {
    padding: 0.75rem 1rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.15), rgba(138, 43, 226, 0.1));
    border-bottom: 1px solid var(--border-gold);
    border-radius: 10px 10px 0 0;
    cursor: move;
    user-select: none;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  
  .header-info {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .chat-icon {
    font-size: 1.1rem;
  }
  
  .chat-title {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.95rem;
  }
  
  .presence-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
  }
  
  .presence-dot.online {
    background: #4caf50;
    box-shadow: 0 0 6px rgba(76, 175, 80, 0.6);
  }
  
  .presence-dot.offline {
    background: #757575;
  }
  
  .header-controls {
    display: flex;
    gap: 0.5rem;
  }
  
  .control-btn {
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    color: var(--text-scripture);
    width: 24px;
    height: 24px;
    border-radius: 4px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.9rem;
    transition: all 0.2s;
  }
  
  .control-btn:hover {
    background: rgba(255, 255, 255, 0.2);
    color: var(--text-divine);
  }
  
  .control-btn.close:hover {
    background: rgba(255, 107, 107, 0.3);
    border-color: rgba(255, 107, 107, 0.5);
  }
  
  .chat-body {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }
  
  .resize-handle {
    position: absolute;
    bottom: 0;
    right: 0;
    width: 20px;
    height: 20px;
    cursor: nwse-resize;
    background: linear-gradient(135deg, transparent 50%, var(--border-gold) 50%);
    border-radius: 0 0 10px 0;
    opacity: 0.5;
    transition: opacity 0.2s;
  }
  
  .resize-handle:hover {
    opacity: 1;
  }
  
  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .loading, .no-messages {
    text-align: center;
    color: var(--text-scripture);
    padding: 2rem;
  }
  
  .no-messages p {
    margin: 0.5rem 0;
    font-size: 0.9rem;
  }
  
  .message {
    display: flex;
    margin-bottom: 0.5rem;
  }
  
  .message.mine {
    justify-content: flex-end;
  }
  
  .message.theirs {
    justify-content: flex-start;
  }
  
  .message-bubble {
    max-width: 70%;
    padding: 0.5rem 0.75rem;
    border-radius: 12px;
    font-size: 0.9rem;
  }
  
  .mine .message-bubble {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 193, 7, 0.1));
    border: 1px solid rgba(255, 215, 0, 0.3);
    color: var(--text-divine);
  }
  
  .theirs .message-bubble {
    background: rgba(138, 43, 226, 0.1);
    border: 1px solid rgba(138, 43, 226, 0.2);
    color: var(--text-light);
  }
  
  .message-text {
    word-wrap: break-word;
    line-height: 1.3;
  }
  
  .message-time {
    font-size: 0.65rem;
    opacity: 0.7;
    margin-top: 0.25rem;
  }
  
  .chat-input {
    padding: 0.75rem;
    border-top: 1px solid var(--border-gold);
    display: flex;
    gap: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
  }
  
  .message-input {
    flex: 1;
    padding: 0.5rem;
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    border-radius: 6px;
    font-size: 0.9rem;
  }
  
  .message-input:focus {
    outline: none;
    border-color: var(--border-gold);
    background: rgba(255, 215, 0, 0.1);
  }
  
  .send-btn {
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 6px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.9rem;
  }
  
  .send-btn:hover:not(:disabled) {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(255, 215, 0, 0.3);
  }
  
  .send-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  /* Mobile responsive */
  @media (max-width: 768px) {
    .chat-popout.mobile {
      width: calc(100vw - 2rem) !important;
      max-width: 400px;
      position: fixed !important;
    }
    
    .chat-popout.mobile:not(.minimized):not(.dragging) {
      height: 70vh !important;
      max-height: 600px;
      left: 50% !important;
      top: 50% !important;
      transform: translate(-50%, -50%) !important;
    }
    
    .chat-popout.mobile.minimized:not(.dragging) {
      width: 250px !important;
      height: auto !important;
      min-height: auto !important;
      left: 50% !important;
      top: 1rem !important;
      transform: translateX(-50%) !important;
    }
    
    .chat-popout.mobile.dragging {
      /* When dragging, use the position from JavaScript */
      transform: none !important;
    }
    
    .resize-handle {
      display: none; /* Hide resize on mobile */
    }
    
    .chat-header {
      touch-action: none; /* Prevent scrolling while dragging */
    }
  }
  
  /* Scrollbar styling */
  .messages-container::-webkit-scrollbar {
    width: 6px;
  }
  
  .messages-container::-webkit-scrollbar-track {
    background: rgba(0, 0, 0, 0.3);
    border-radius: 3px;
  }
  
  .messages-container::-webkit-scrollbar-thumb {
    background: var(--border-gold);
    border-radius: 3px;
  }
  
  .messages-container::-webkit-scrollbar-thumb:hover {
    background: var(--primary-gold);
  }
</style>