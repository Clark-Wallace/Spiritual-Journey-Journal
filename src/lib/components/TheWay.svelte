<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  let messages: any[] = [];
  let onlineUsers: any[] = [];
  let newMessage = '';
  let loading = true;
  let messagesContainer: HTMLDivElement;
  let userStatus: 'online' | 'away' | 'praying' | 'reading' = 'online';
  let subscription: any;
  let presenceSubscription: any;
  
  const statusEmojis = {
    online: '🟢',
    away: '🟡',
    praying: '🙏',
    reading: '📖'
  };
  
  onMount(async () => {
    await loadMessages();
    await updatePresence();
    setupRealtimeSubscriptions();
    
    // Update presence every 30 seconds
    const presenceInterval = setInterval(updatePresence, 30000);
    
    return () => {
      clearInterval(presenceInterval);
      cleanupSubscriptions();
    };
  });
  
  onDestroy(() => {
    cleanupSubscriptions();
  });
  
  function setupRealtimeSubscriptions() {
    // Subscribe to new messages
    subscription = supabase
      .channel('the-way-chat')
      .on('postgres_changes', 
        { event: 'INSERT', schema: 'public', table: 'chat_messages' },
        (payload) => {
          console.log('New message received:', payload);
          messages = [...messages, payload.new];
          scrollToBottom();
        }
      )
      .on('postgres_changes',
        { event: 'DELETE', schema: 'public', table: 'chat_messages' },
        (payload) => {
          messages = messages.filter(m => m.id !== payload.old.id);
        }
      )
      .subscribe((status) => {
        console.log('Subscription status:', status);
      });
    
    // Subscribe to presence updates
    presenceSubscription = supabase
      .channel('online-users')
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'user_presence' },
        () => loadOnlineUsers()
      )
      .subscribe();
  }
  
  function cleanupSubscriptions() {
    if (subscription) {
      supabase.removeChannel(subscription);
    }
    if (presenceSubscription) {
      supabase.removeChannel(presenceSubscription);
    }
  }
  
  async function loadMessages() {
    loading = true;
    
    const { data, error } = await supabase
      .from('chat_messages')
      .select(`
        *,
        chat_reactions (
          reaction,
          user_id
        )
      `)
      .order('created_at', { ascending: true })
      .limit(100);
    
    if (error) {
      console.error('Error loading messages:', error);
      alert('Error loading messages: ' + error.message);
    } else {
      messages = data || [];
      console.log('Loaded messages:', messages);
      setTimeout(scrollToBottom, 100);
    }
    
    loading = false;
  }
  
  async function loadOnlineUsers() {
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();
    
    const { data, error } = await supabase
      .from('user_presence')
      .select('*')
      .gte('last_seen', fiveMinutesAgo)
      .order('last_seen', { ascending: false });
    
    if (!error) {
      onlineUsers = data || [];
    }
  }
  
  async function updatePresence() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('user_presence')
      .upsert({
        user_id: user.id,
        user_name: user.user_metadata?.name || user.email?.split('@')[0],
        status: userStatus,
        last_seen: new Date().toISOString()
      }, {
        onConflict: 'user_id'
      });
    
    if (!error) {
      await loadOnlineUsers();
    }
  }
  
  async function sendMessage() {
    if (!newMessage.trim()) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const isPrayerRequest = newMessage.toLowerCase().includes('pray') || 
                           newMessage.toLowerCase().includes('need prayer');
    
    const { error } = await supabase
      .from('chat_messages')
      .insert({
        user_id: user.id,
        user_name: user.user_metadata?.name || user.email?.split('@')[0],
        message: newMessage,
        is_prayer_request: isPrayerRequest
      });
    
    if (error) {
      console.error('Error sending message:', error);
      alert('Error sending message: ' + error.message);
    } else {
      newMessage = '';
      console.log('Message sent successfully');
    }
  }
  
  async function addReaction(messageId: string, reaction: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('chat_reactions')
      .insert({
        message_id: messageId,
        user_id: user.id,
        reaction
      });
    
    if (!error) {
      await loadMessages();
    }
  }
  
  async function deleteMessage(messageId: string) {
    const { error } = await supabase
      .from('chat_messages')
      .delete()
      .eq('id', messageId);
    
    if (error) {
      console.error('Error deleting message:', error);
    }
  }
  
  function scrollToBottom() {
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
  }
  
  function formatTime(date: string) {
    const d = new Date(date);
    return d.toLocaleTimeString('en-US', { 
      hour: 'numeric', 
      minute: '2-digit',
      hour12: true 
    });
  }
  
  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendMessage();
    }
  }
</script>

<div class="the-way-container">
  <div class="chat-header">
    <div class="header-info">
      <h2>✝️ The Way</h2>
      <p class="subtitle">Fellowship & Prayer Chat</p>
    </div>
    <div class="status-selector">
      <select bind:value={userStatus} on:change={updatePresence}>
        <option value="online">🟢 Online</option>
        <option value="away">🟡 Away</option>
        <option value="praying">🙏 Praying</option>
        <option value="reading">📖 Reading Scripture</option>
      </select>
    </div>
  </div>
  
  <div class="chat-body">
    <div class="messages-section">
      {#if loading}
        <div class="loading">Loading messages...</div>
      {:else}
        <div class="messages-container" bind:this={messagesContainer}>
          {#if messages.length === 0}
            <div class="welcome-message">
              <h3>Welcome to The Way!</h3>
              <p>Be the first to share a word of encouragement or prayer request.</p>
              <p class="verse">"For where two or three gather in my name, there am I with them." - Matthew 18:20</p>
            </div>
          {:else}
            {#each messages as message}
              <div class="message" class:own-message={message.user_id === $authStore?.id}>
                <div class="message-header">
                  <span class="user-name">{message.user_name}</span>
                  <span class="time">{formatTime(message.created_at)}</span>
                  {#if message.user_id === $authStore?.id}
                    <button class="delete-btn" on:click={() => deleteMessage(message.id)}>×</button>
                  {/if}
                </div>
                <div class="message-content" class:prayer-request={message.is_prayer_request}>
                  {#if message.is_prayer_request}
                    <span class="prayer-badge">🙏 Prayer Request</span>
                  {/if}
                  {message.message}
                </div>
                <div class="message-reactions">
                  <button class="reaction-btn" on:click={() => addReaction(message.id, 'amen')}>
                    🙏 Amen
                  </button>
                  <button class="reaction-btn" on:click={() => addReaction(message.id, 'pray')}>
                    🤲 Praying
                  </button>
                  <button class="reaction-btn" on:click={() => addReaction(message.id, 'love')}>
                    ❤️ Love
                  </button>
                </div>
              </div>
            {/each}
          {/if}
        </div>
      {/if}
      
      <div class="message-input-container">
        <textarea
          bind:value={newMessage}
          on:keydown={handleKeydown}
          placeholder="Share a message, prayer request, or encouragement..."
          rows="2"
        ></textarea>
        <button class="send-btn" on:click={sendMessage}>
          Send 📤
        </button>
      </div>
    </div>
    
    <div class="sidebar">
      <div class="online-users">
        <h3>🫂 Online ({onlineUsers.length})</h3>
        <div class="users-list">
          {#each onlineUsers as user}
            <div class="user-item">
              <span class="status-icon">{statusEmojis[user.status]}</span>
              <span class="user-name">{user.user_name}</span>
            </div>
          {/each}
        </div>
      </div>
      
      <div class="chat-guidelines">
        <h4>Community Guidelines</h4>
        <ul>
          <li>Love one another (John 13:34)</li>
          <li>Encourage & build up (1 Thess 5:11)</li>
          <li>Pray for each other (James 5:16)</li>
          <li>Be kind & compassionate (Eph 4:32)</li>
        </ul>
      </div>
    </div>
  </div>
</div>

<style>
  .the-way-container {
    max-width: 1200px;
    margin: 0 auto;
    height: calc(100vh - 200px);
    display: flex;
    flex-direction: column;
  }
  
  .chat-header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 1rem 1.5rem;
    border-radius: 12px 12px 0 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  
  .header-info h2 {
    margin: 0;
    font-size: 1.5rem;
  }
  
  .subtitle {
    margin: 0.25rem 0 0;
    opacity: 0.9;
    font-size: 0.9rem;
  }
  
  .status-selector select {
    padding: 0.5rem;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.2);
    color: white;
    cursor: pointer;
  }
  
  .chat-body {
    flex: 1;
    display: flex;
    background: white;
    border-radius: 0 0 12px 12px;
    overflow: hidden;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  }
  
  .messages-section {
    flex: 1;
    display: flex;
    flex-direction: column;
  }
  
  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    background: #f8f9fa;
  }
  
  .welcome-message {
    text-align: center;
    padding: 3rem;
    color: #666;
  }
  
  .welcome-message h3 {
    color: #667eea;
    margin-bottom: 1rem;
  }
  
  .verse {
    font-style: italic;
    color: #999;
    margin-top: 1rem;
  }
  
  .message {
    background: white;
    border-radius: 8px;
    padding: 0.75rem 1rem;
    margin-bottom: 0.75rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }
  
  .message.own-message {
    background: #e3f2fd;
    margin-left: 20%;
  }
  
  .message-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
    font-size: 0.85rem;
  }
  
  .message-header .user-name {
    font-weight: 600;
    color: #667eea;
  }
  
  .message-header .time {
    color: #999;
    font-size: 0.8rem;
  }
  
  .delete-btn {
    margin-left: auto;
    background: none;
    border: none;
    color: #999;
    cursor: pointer;
    font-size: 1.2rem;
    padding: 0 0.25rem;
  }
  
  .delete-btn:hover {
    color: #f44336;
  }
  
  .message-content {
    line-height: 1.5;
    word-wrap: break-word;
  }
  
  .message-content.prayer-request {
    background: #fff3e0;
    padding: 0.5rem;
    border-radius: 6px;
    border-left: 3px solid #ff9800;
  }
  
  .prayer-badge {
    display: inline-block;
    font-size: 0.8rem;
    font-weight: 600;
    margin-bottom: 0.25rem;
    color: #ff9800;
  }
  
  .message-reactions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }
  
  .reaction-btn {
    padding: 0.25rem 0.5rem;
    background: #f5f5f5;
    border: none;
    border-radius: 12px;
    cursor: pointer;
    font-size: 0.85rem;
    transition: all 0.2s;
  }
  
  .reaction-btn:hover {
    background: #e0e0e0;
    transform: scale(1.05);
  }
  
  .message-input-container {
    display: flex;
    gap: 0.5rem;
    padding: 1rem;
    background: white;
    border-top: 1px solid #e0e0e0;
  }
  
  .message-input-container textarea {
    flex: 1;
    padding: 0.75rem;
    border: 1px solid #ddd;
    border-radius: 8px;
    font-family: inherit;
    resize: none;
  }
  
  .send-btn {
    padding: 0.75rem 1.5rem;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    transition: background 0.2s;
  }
  
  .send-btn:hover {
    background: #5a72d8;
  }
  
  .sidebar {
    width: 250px;
    background: #f8f9fa;
    border-left: 1px solid #e0e0e0;
    padding: 1rem;
    overflow-y: auto;
  }
  
  .online-users h3 {
    margin: 0 0 1rem 0;
    font-size: 1rem;
    color: #333;
  }
  
  .users-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  
  .user-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem;
    background: white;
    border-radius: 6px;
  }
  
  .status-icon {
    font-size: 0.8rem;
  }
  
  .user-item .user-name {
    font-size: 0.9rem;
  }
  
  .chat-guidelines {
    margin-top: 2rem;
    padding-top: 1rem;
    border-top: 1px solid #ddd;
  }
  
  .chat-guidelines h4 {
    margin: 0 0 0.5rem 0;
    font-size: 0.9rem;
    color: #667eea;
  }
  
  .chat-guidelines ul {
    margin: 0;
    padding-left: 1.5rem;
    font-size: 0.85rem;
    color: #666;
  }
  
  .chat-guidelines li {
    margin-bottom: 0.25rem;
  }
  
  .loading {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100%;
    color: #999;
  }
  
  @media (max-width: 768px) {
    .sidebar {
      display: none;
    }
    
    .message.own-message {
      margin-left: 10%;
    }
  }
</style>