<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  export let isOpen = false;
  export let recipientId: string | null = null;
  export let recipientName: string = '';
  
  let messages: any[] = [];
  let newMessage = '';
  let loading = false;
  let messagesContainer: HTMLDivElement;
  let subscription: any;
  
  $: if (isOpen && recipientId) {
    loadMessages();
    setupRealtimeSubscription();
  }
  
  onDestroy(() => {
    if (subscription) {
      subscription.unsubscribe();
    }
  });
  
  async function loadMessages() {
    if (!recipientId) return;
    
    loading = true;
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('get_conversation_messages', {
        p_user_id: user.id,
        p_other_user_id: recipientId,
        p_limit: 50,
        p_offset: 0
      });
    
    if (!error && data) {
      messages = data.reverse(); // Show oldest first
      scrollToBottom();
    }
    
    loading = false;
  }
  
  async function sendMessage() {
    if (!newMessage.trim() || !recipientId) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('private_messages')
      .insert({
        from_user_id: user.id,
        to_user_id: recipientId,
        message: newMessage.trim()
      })
      .select()
      .single();
    
    if (!error && data) {
      newMessage = '';
      // Message will appear via realtime subscription
    } else {
      console.error('Error sending message:', error);
    }
  }
  
  function setupRealtimeSubscription() {
    if (subscription) {
      subscription.unsubscribe();
    }
    
    const user = $authStore;
    if (!user || !recipientId) return;
    
    subscription = supabase
      .channel(`private-messages-${user.id}-${recipientId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'private_messages',
        filter: `from_user_id=eq.${user.id},to_user_id=eq.${recipientId}`
      }, (payload) => {
        const newMsg = {
          ...payload.new,
          from_user_name: $userInfo?.name || 'You',
          to_user_name: recipientName,
          is_mine: true
        };
        messages = [...messages, newMsg];
        scrollToBottom();
      })
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'private_messages',
        filter: `from_user_id=eq.${recipientId},to_user_id=eq.${user.id}`
      }, (payload) => {
        const newMsg = {
          ...payload.new,
          from_user_name: recipientName,
          to_user_name: $userInfo?.name || 'You',
          is_mine: false
        };
        messages = [...messages, newMsg];
        scrollToBottom();
        
        // Mark as read
        markAsRead(payload.new.id);
      })
      .subscribe();
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
  
  function close() {
    isOpen = false;
    recipientId = null;
    recipientName = '';
    messages = [];
    if (subscription) {
      subscription.unsubscribe();
      subscription = null;
    }
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
</script>

{#if isOpen}
  <div class="dm-overlay" on:click={close}>
    <div class="dm-container" on:click|stopPropagation>
      <div class="dm-header">
        <h3>💬 Private Message with {recipientName}</h3>
        <button class="close-btn" on:click={close}>✕</button>
      </div>
      
      <div class="dm-messages" bind:this={messagesContainer}>
        {#if loading}
          <div class="loading">Loading messages...</div>
        {:else if messages.length === 0}
          <div class="no-messages">
            <p>No messages yet</p>
            <p>Send a message to start the conversation!</p>
          </div>
        {:else}
          {#each messages as message}
            <div class="dm-message {message.is_mine ? 'mine' : 'theirs'}">
              <div class="message-bubble">
                <div class="message-text">{message.message}</div>
                <div class="message-time">{formatTime(message.created_at)}</div>
              </div>
            </div>
          {/each}
        {/if}
      </div>
      
      <div class="dm-input">
        <input
          type="text"
          bind:value={newMessage}
          placeholder="Type your message..."
          on:keydown={(e) => e.key === 'Enter' && sendMessage()}
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
  </div>
{/if}

<style>
  .dm-overlay {
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
    z-index: 2000;
    padding: 1rem;
  }
  
  .dm-container {
    background: linear-gradient(135deg, #1a1a2e, #0f0f1e);
    border: 2px solid var(--border-gold);
    border-radius: 15px;
    width: 100%;
    max-width: 500px;
    height: 600px;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.8),
                0 0 40px rgba(255, 215, 0, 0.2);
  }
  
  .dm-header {
    padding: 1rem 1.5rem;
    border-bottom: 1px solid var(--border-gold);
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(138, 43, 226, 0.05));
  }
  
  .dm-header h3 {
    margin: 0;
    color: var(--text-divine);
    font-size: 1.2rem;
  }
  
  .close-btn {
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 1.5rem;
    cursor: pointer;
    transition: all 0.2s;
    padding: 0;
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  
  .close-btn:hover {
    color: var(--text-divine);
    transform: scale(1.1);
  }
  
  .dm-messages {
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
  }
  
  .dm-message {
    display: flex;
    margin-bottom: 0.5rem;
  }
  
  .dm-message.mine {
    justify-content: flex-end;
  }
  
  .dm-message.theirs {
    justify-content: flex-start;
  }
  
  .message-bubble {
    max-width: 70%;
    padding: 0.75rem 1rem;
    border-radius: 15px;
    position: relative;
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
    line-height: 1.4;
  }
  
  .message-time {
    font-size: 0.7rem;
    opacity: 0.7;
    margin-top: 0.25rem;
  }
  
  .dm-input {
    padding: 1rem;
    border-top: 1px solid var(--border-gold);
    display: flex;
    gap: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
  }
  
  .message-input {
    flex: 1;
    padding: 0.75rem;
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    border-radius: 8px;
    font-size: 1rem;
  }
  
  .message-input:focus {
    outline: none;
    border-color: var(--border-gold);
    background: rgba(255, 215, 0, 0.1);
  }
  
  .send-btn {
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 8px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .send-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
  }
  
  .send-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  /* Mobile responsive */
  @media (max-width: 768px) {
    .dm-container {
      max-width: 100%;
      height: 100%;
      max-height: 100%;
      border-radius: 0;
    }
    
    .dm-overlay {
      padding: 0;
    }
  }
  
  /* Scrollbar styling */
  .dm-messages::-webkit-scrollbar {
    width: 8px;
  }
  
  .dm-messages::-webkit-scrollbar-track {
    background: rgba(0, 0, 0, 0.3);
    border-radius: 4px;
  }
  
  .dm-messages::-webkit-scrollbar-thumb {
    background: var(--border-gold);
    border-radius: 4px;
  }
  
  .dm-messages::-webkit-scrollbar-thumb:hover {
    background: var(--primary-gold);
  }
</style>