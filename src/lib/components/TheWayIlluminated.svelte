<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  import { currentView } from '../stores';
  
  let messages: any[] = [];
  let onlineUsers: any[] = [];
  let newMessage = '';
  let loading = true;
  let messagesContainer: HTMLDivElement;
  let userStatus: 'online' | 'praying' | 'reading' | 'away' = 'online';
  let subscription: any;
  let presenceSubscription: any;
  
  // Chat rooms
  interface ChatRoom {
    id: string;
    name: string;
    icon: string;
  }
  
  const rooms: ChatRoom[] = [
    { id: 'fellowship', name: 'Fellowship Hall', icon: '⛪' },
    { id: 'prayer', name: 'Prayer Chamber', icon: '🙏' },
    { id: 'scripture', name: 'Scripture Study', icon: '📖' },
    { id: 'testimony', name: 'Testimony', icon: '✨' },
    { id: 'worship', name: 'Worship', icon: '🎵' }
  ];
  
  let currentRoom = rooms[0];
  
  const statusConfig = {
    online: { icon: '✨', label: 'Walking in faith', color: '#4caf50' },
    praying: { icon: '🙏', label: 'In prayer', color: '#ffa726' },
    reading: { icon: '📖', label: 'Reading Word', color: '#42a5f5' },
    away: { icon: '🕊️', label: 'Away', color: '#bdbdbd' }
  };
  
  onMount(async () => {
    await loadMessages();
    await updatePresence();
    setupRealtimeSubscriptions();
    
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
    subscription = supabase
      .channel('the-way-illuminated')
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
    
    presenceSubscription = supabase
      .channel('online-souls')
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
      .eq('room', currentRoom.id)
      .order('created_at', { ascending: true })
      .limit(100);
    
    if (error) {
      console.error('Error loading messages:', error);
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
        room: currentRoom.id,
        user_id: user.id,
        user_name: user.user_metadata?.name || user.email?.split('@')[0],
        message: newMessage,
        is_prayer_request: isPrayerRequest
      });
    
    if (error) {
      console.error('Error sending message:', error);
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
  
  function switchRoom(room: ChatRoom) {
    currentRoom = room;
    messages = [];
    loadMessages();
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
  
  function getInitials(name: string) {
    return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
  
  function exitChat() {
    $currentView = 'home';
  }
</script>

<div class="sanctuary-container">
  <!-- Sidebar - Sacred Style -->
  <div class="sidebar">
    <div class="sidebar-header">
      <div class="sanctuary-emblem">⛪</div>
      <div class="sanctuary-title">THE WAY</div>
      <div class="sanctuary-subtitle">Where souls gather in His light</div>
      <button class="exit-sanctuary" on:click={exitChat} title="Return to main app">
        ← Exit
      </button>
    </div>
    
    <div class="congregation">
      <div class="section-divider">Gathered Souls • {onlineUsers.length}</div>
      
      {#each onlineUsers as user}
        <div class="soul-vessel">
          <div class="soul-avatar">
            {getInitials(user.user_name || 'Anonymous')}
            <div class="presence-aura aura-{user.status || 'online'}"></div>
          </div>
          <div class="soul-details">
            <div class="soul-name">{user.user_name || 'Anonymous Soul'}</div>
            <div class="soul-message">
              {statusConfig[user.status || 'online'].icon} {statusConfig[user.status || 'online'].label}
            </div>
          </div>
        </div>
      {/each}
      
      {#if onlineUsers.length === 0}
        <div class="empty-congregation">
          Awaiting fellowship...
        </div>
      {/if}
    </div>
    
    <div class="sacred-scrolls">
      <div class="section-divider">Sacred Covenant</div>
      <div class="scroll-item">Love one another as He loved us</div>
      <div class="scroll-item">Bear each other's burdens</div>
      <div class="scroll-item">Encourage with psalms & hymns</div>
      <div class="scroll-item">Speak truth wrapped in grace</div>
    </div>
    
    <div class="status-selector">
      <label>Your Presence:</label>
      <select bind:value={userStatus} on:change={updatePresence} class="status-select">
        <option value="online">✨ Walking in faith</option>
        <option value="praying">🙏 In prayer</option>
        <option value="reading">📖 Reading Word</option>
        <option value="away">🕊️ Away</option>
      </select>
    </div>
  </div>
  
  <!-- Main Sanctuary -->
  <div class="sanctuary-hall">
    <div class="sanctuary-ceiling">
      <div class="hall-inscription">
        <div class="hall-name">✨ {currentRoom.name} ✨</div>
        <div class="divine-verse">"Behold, how good and pleasant it is when brothers dwell in unity!" - Psalm 133:1</div>
      </div>
    </div>
    
    <!-- Sacred Room Chambers -->
    <div class="chamber-selection">
      {#each rooms as room}
        <button 
          class="chamber-portal"
          class:active={currentRoom.id === room.id}
          on:click={() => switchRoom(room)}
        >
          <span class="chamber-icon">{room.icon}</span>
          <span class="chamber-name">{room.name}</span>
        </button>
      {/each}
    </div>
    
    <div class="sacred-chamber" bind:this={messagesContainer}>
      {#if loading}
        <div class="loading-divine">
          <div class="loading-emblem">🕊️</div>
          <div>Loading sacred messages...</div>
        </div>
      {:else if messages.length === 0}
        <div class="welcome-illumination">
          <h2>Welcome to The Way</h2>
          <p>A sacred digital space where hearts unite in prayer and fellowship</p>
          <p class="verse-inscription">
            "For where two or three gather in my name, there am I with them." - Matthew 18:20
          </p>
        </div>
      {:else}
        {#each messages as message}
          <div class="divine-message">
            <div class="messenger-seal">
              {getInitials(message.user_name || 'Anonymous')}
            </div>
            <div class="message-scroll">
              <div class="scroll-header">
                <span class="messenger-name">{message.user_name || 'Anonymous Soul'}</span>
                <span class="message-timestamp">{formatTime(message.created_at)}</span>
                {#if message.user_id === $authStore?.id}
                  <button class="delete-whisper" on:click={() => deleteMessage(message.id)}>×</button>
                {/if}
              </div>
              <div class="scroll-text" class:prayer-illumination={message.is_prayer_request}>
                {#if message.is_prayer_request}
                  <div class="prayer-label">🙏 PRAYER REQUEST</div>
                {/if}
                {message.message}
              </div>
              <div class="blessings-received">
                <button class="blessing" on:click={() => addReaction(message.id, 'amen')}>
                  <span>🙏</span>
                  <span class="blessing-count">Amen</span>
                </button>
                <button class="blessing" on:click={() => addReaction(message.id, 'pray')}>
                  <span>🤲</span>
                  <span class="blessing-count">Praying</span>
                </button>
                <button class="blessing" on:click={() => addReaction(message.id, 'love')}>
                  <span>❤️</span>
                  <span class="blessing-count">Love</span>
                </button>
                <button class="blessing" on:click={() => addReaction(message.id, 'hallelujah')}>
                  <span>🎉</span>
                  <span class="blessing-count">Hallelujah</span>
                </button>
              </div>
            </div>
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="prayer-altar">
      <div class="altar-vessel">
        <textarea 
          class="prayer-inscription" 
          bind:value={newMessage}
          on:keydown={handleKeydown}
          placeholder="Inscribe your prayer, testimony, or word of encouragement..."
          rows="2"
        ></textarea>
        <div class="altar-tools">
          <button class="altar-tool" title="Add Scripture">📜</button>
          <button class="altar-tool" title="Mark as Prayer">🕊️</button>
          <button class="altar-tool send-prayer" on:click={sendMessage}>
            <span>Lift Up</span>
            <span class="send-icon">✨</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .sanctuary-container {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    height: 100vh;
    width: 100vw;
    display: flex;
    background: linear-gradient(180deg, var(--bg-dark) 0%, var(--bg-dark-secondary) 100%);
    z-index: 1000;
    overflow: hidden;
  }
  
  /* Sidebar */
  .sidebar {
    width: 280px;
    background: linear-gradient(180deg, rgba(10, 10, 15, 0.98), rgba(15, 15, 25, 0.98));
    backdrop-filter: blur(20px);
    display: flex;
    flex-direction: column;
    border-right: 2px solid;
    border-image: linear-gradient(180deg, 
      rgba(255, 215, 0, 0.3), 
      rgba(138, 43, 226, 0.3), 
      rgba(30, 144, 255, 0.3)) 1;
  }
  
  .sidebar-header {
    padding: 25px 20px;
    text-align: center;
    background: radial-gradient(ellipse at center, rgba(255, 215, 0, 0.1), transparent);
    border-bottom: 1px solid var(--border-gold);
  }
  
  .sanctuary-emblem {
    font-size: 48px;
    margin-bottom: 10px;
    filter: drop-shadow(0 0 20px rgba(255, 215, 0, 0.5));
    animation: glow 3s ease-in-out infinite;
  }
  
  .sanctuary-title {
    color: transparent;
    background: linear-gradient(180deg, #ffd700, #ffed4e);
    -webkit-background-clip: text;
    background-clip: text;
    font-size: 24px;
    font-weight: 700;
    letter-spacing: 2px;
    margin-bottom: 5px;
  }
  
  .sanctuary-subtitle {
    color: var(--text-scripture);
    font-size: 11px;
    font-style: italic;
    letter-spacing: 1px;
  }
  
  .exit-sanctuary {
    position: absolute;
    top: 10px;
    right: 10px;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid var(--border-gold);
    color: var(--text-divine);
    padding: 6px 12px;
    border-radius: 6px;
    font-size: 12px;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .exit-sanctuary:hover {
    background: rgba(255, 215, 0, 0.2);
    transform: scale(1.05);
    box-shadow: 0 0 10px rgba(255, 215, 0, 0.3);
  }
  
  .congregation {
    flex: 1;
    overflow-y: auto;
    padding: 20px 15px;
  }
  
  .soul-vessel {
    display: flex;
    align-items: center;
    padding: 12px;
    margin-bottom: 8px;
    border-radius: 10px;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.05));
    border: 1px solid transparent;
    cursor: pointer;
    transition: all 0.4s;
    position: relative;
  }
  
  .soul-vessel:hover {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(30, 144, 255, 0.1));
    border-color: var(--border-gold);
    transform: translateX(5px);
  }
  
  .soul-avatar {
    width: 42px;
    height: 42px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.2), rgba(138, 43, 226, 0.2));
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-weight: bold;
    margin-right: 12px;
    position: relative;
    box-shadow: 0 0 20px rgba(138, 43, 226, 0.3);
  }
  
  .presence-aura {
    position: absolute;
    bottom: -2px;
    right: -2px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid var(--bg-dark);
    animation: pulse 2s infinite;
  }
  
  .aura-online { background: #4caf50; }
  .aura-praying { background: #ff9800; }
  .aura-reading { background: #2196f3; }
  .aura-away { background: #bdbdbd; }
  
  .soul-details {
    flex: 1;
  }
  
  .soul-name {
    color: var(--text-light);
    font-size: 14px;
    font-weight: 500;
    margin-bottom: 3px;
  }
  
  .soul-message {
    color: var(--text-scripture);
    font-size: 11px;
    font-style: italic;
  }
  
  .empty-congregation {
    text-align: center;
    color: var(--text-scripture);
    font-style: italic;
    padding: 20px;
  }
  
  .sacred-scrolls {
    padding: 20px 15px;
    background: linear-gradient(180deg, rgba(138, 43, 226, 0.05), rgba(10, 10, 15, 0.98));
    border-top: 1px solid var(--border-gold);
  }
  
  .scroll-item {
    color: var(--text-scripture);
    font-size: 11px;
    line-height: 1.8;
    padding-left: 20px;
    position: relative;
    margin-bottom: 5px;
  }
  
  .scroll-item::before {
    content: '†';
    position: absolute;
    left: 5px;
    color: var(--border-gold-strong);
  }
  
  .status-selector {
    padding: 15px;
    border-top: 1px solid var(--border-gold);
    background: rgba(255, 215, 0, 0.03);
  }
  
  .status-selector label {
    display: block;
    color: var(--text-scripture);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 8px;
  }
  
  .status-select {
    width: 100%;
    padding: 8px;
    background: rgba(255, 215, 0, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 6px;
    color: var(--text-holy);
    font-size: 13px;
    cursor: pointer;
  }
  
  /* Main Sanctuary */
  .sanctuary-hall {
    flex: 1;
    display: flex;
    flex-direction: column;
    position: relative;
  }
  
  .sanctuary-ceiling {
    background: linear-gradient(180deg, rgba(10, 10, 15, 0.95), rgba(20, 20, 35, 0.9));
    backdrop-filter: blur(10px);
    padding: 20px 25px;
    border-bottom: 1px solid;
    border-image: linear-gradient(90deg, transparent, var(--border-gold), transparent) 1;
  }
  
  .hall-inscription {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  
  /* Sacred Room Chambers */
  .chamber-selection {
    display: flex;
    gap: 2px;
    padding: 0 20px;
    background: linear-gradient(180deg, rgba(20, 20, 35, 0.95), rgba(15, 15, 25, 0.9));
    border-bottom: 1px solid;
    border-image: linear-gradient(90deg, transparent, var(--border-gold), transparent) 1;
    overflow-x: auto;
    scrollbar-width: thin;
    scrollbar-color: var(--border-gold) transparent;
  }
  
  .chamber-selection::-webkit-scrollbar {
    height: 4px;
  }
  
  .chamber-selection::-webkit-scrollbar-track {
    background: transparent;
  }
  
  .chamber-selection::-webkit-scrollbar-thumb {
    background: var(--border-gold);
    border-radius: 2px;
  }
  
  .chamber-portal {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 10px 16px;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.05), rgba(138, 43, 226, 0.05));
    border: 1px solid transparent;
    border-bottom: 2px solid transparent;
    color: var(--text-scripture);
    font-size: 13px;
    cursor: pointer;
    transition: all 0.3s;
    position: relative;
    white-space: nowrap;
  }
  
  .chamber-portal::before {
    content: '';
    position: absolute;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 0;
    height: 2px;
    background: linear-gradient(90deg, transparent, var(--primary-gold), transparent);
    transition: width 0.3s;
  }
  
  .chamber-portal:hover {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(138, 43, 226, 0.08));
    color: var(--text-holy);
  }
  
  .chamber-portal:hover::before {
    width: 100%;
  }
  
  .chamber-portal.active {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.15), rgba(138, 43, 226, 0.1));
    border-bottom-color: var(--primary-gold);
    color: var(--text-divine);
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.3);
  }
  
  .chamber-portal.active::before {
    width: 100%;
    height: 3px;
    background: var(--primary-gold);
    box-shadow: 0 0 10px rgba(255, 215, 0, 0.5);
  }
  
  .chamber-icon {
    font-size: 16px;
    filter: drop-shadow(0 0 4px currentColor);
  }
  
  .chamber-portal.active .chamber-icon {
    filter: drop-shadow(0 0 8px rgba(255, 215, 0, 0.5));
    animation: pulse 2s infinite;
  }
  
  .chamber-name {
    font-weight: 500;
    letter-spacing: 0.5px;
  }
  
  .hall-name {
    font-size: 22px;
    color: transparent;
    background: linear-gradient(90deg, #ffd700, #fff, #ffd700);
    -webkit-background-clip: text;
    background-clip: text;
    font-weight: 600;
    letter-spacing: 1px;
  }
  
  .divine-verse {
    color: var(--text-scripture);
    font-size: 12px;
    font-style: italic;
    max-width: 400px;
  }
  
  .sacred-chamber {
    flex: 1;
    overflow-y: auto;
    padding: 30px;
    background: radial-gradient(ellipse at center top, rgba(138, 43, 226, 0.05), transparent 50%);
  }
  
  .loading-divine {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-scripture);
  }
  
  .loading-emblem {
    font-size: 48px;
    animation: float 3s ease-in-out infinite;
    margin-bottom: 20px;
  }
  
  @keyframes float {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
  }
  
  .welcome-illumination {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid var(--border-gold);
    border-radius: 15px;
    padding: 30px;
    text-align: center;
    margin: 50px auto;
    max-width: 600px;
    position: relative;
    overflow: hidden;
  }
  
  .welcome-illumination::before {
    content: '';
    position: absolute;
    top: -50%;
    left: -50%;
    width: 200%;
    height: 200%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.05) 0%, transparent 70%);
    animation: rotate 20s linear infinite;
  }
  
  @keyframes rotate {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
  
  .welcome-illumination h2 {
    color: var(--text-divine);
    font-size: 24px;
    margin-bottom: 10px;
    text-shadow: var(--shadow-divine);
    position: relative;
  }
  
  .welcome-illumination p {
    color: var(--text-holy);
    line-height: 1.6;
    position: relative;
  }
  
  .verse-inscription {
    color: var(--text-scripture) !important;
    font-style: italic;
    margin-top: 15px;
  }
  
  .divine-message {
    display: flex;
    gap: 15px;
    margin-bottom: 25px;
    padding: 15px;
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.02), rgba(255, 255, 255, 0.01));
    border-radius: 12px;
    position: relative;
    animation: fadeInIlluminate 0.5s ease-out;
  }
  
  .divine-message::before {
    content: '';
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 2px;
    background: linear-gradient(180deg, transparent, rgba(138, 43, 226, 0.5), transparent);
    opacity: 0;
    transition: opacity 0.3s;
  }
  
  .divine-message:hover::before {
    opacity: 1;
  }
  
  .messenger-seal {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.15), rgba(138, 43, 226, 0.15));
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-divine);
    font-weight: bold;
    font-size: 18px;
    box-shadow: 0 0 30px rgba(138, 43, 226, 0.2);
    position: relative;
  }
  
  .messenger-seal::after {
    content: '';
    position: absolute;
    inset: -4px;
    border-radius: 50%;
    border: 1px solid var(--border-gold);
    animation: rotate 10s linear infinite;
  }
  
  .message-scroll {
    flex: 1;
  }
  
  .scroll-header {
    display: flex;
    align-items: baseline;
    gap: 15px;
    margin-bottom: 8px;
  }
  
  .messenger-name {
    color: var(--text-divine);
    font-size: 15px;
    font-weight: 600;
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.3);
  }
  
  .message-timestamp {
    color: var(--text-scripture);
    font-size: 11px;
  }
  
  .delete-whisper {
    margin-left: auto;
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 20px;
    cursor: pointer;
    opacity: 0.5;
    transition: all 0.3s;
  }
  
  .delete-whisper:hover {
    color: #f44336;
    opacity: 1;
  }
  
  .scroll-text {
    color: var(--text-light);
    line-height: 1.6;
    font-size: 14px;
  }
  
  .prayer-illumination {
    background: linear-gradient(135deg, rgba(255, 152, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid rgba(255, 152, 0, 0.3);
    border-radius: 8px;
    padding: 15px;
    margin-top: 10px;
    position: relative;
    overflow: hidden;
  }
  
  .prayer-illumination::before {
    content: '🕊️';
    position: absolute;
    top: -20px;
    right: -20px;
    font-size: 80px;
    opacity: 0.1;
    transform: rotate(-15deg);
  }
  
  .prayer-label {
    color: var(--primary-orange);
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 2px;
    margin-bottom: 8px;
  }
  
  .blessings-received {
    display: flex;
    gap: 8px;
    margin-top: 12px;
  }
  
  .blessing {
    background: radial-gradient(circle, rgba(255, 215, 0, 0.15), transparent);
    border: 1px solid var(--border-gold);
    padding: 5px 12px;
    border-radius: 20px;
    display: flex;
    align-items: center;
    gap: 6px;
    cursor: pointer;
    transition: all 0.3s;
    color: var(--text-holy);
  }
  
  .blessing:hover {
    background: radial-gradient(circle, rgba(255, 215, 0, 0.25), transparent);
    transform: scale(1.05);
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.3);
  }
  
  .blessing-count {
    font-size: 11px;
    font-weight: 600;
  }
  
  /* Prayer Altar */
  .prayer-altar {
    padding: 20px 25px;
    background: linear-gradient(180deg, rgba(20, 20, 35, 0.95), rgba(10, 10, 15, 0.98));
    border-top: 1px solid;
    border-image: linear-gradient(90deg, transparent, var(--border-gold), transparent) 1;
    backdrop-filter: blur(10px);
  }
  
  .altar-vessel {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.05));
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    padding: 12px 15px;
    display: flex;
    align-items: center;
    transition: all 0.3s;
  }
  
  .altar-vessel:focus-within {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(30, 144, 255, 0.1));
    box-shadow: 0 0 30px rgba(255, 215, 0, 0.2);
  }
  
  .prayer-inscription {
    flex: 1;
    background: none;
    border: none;
    color: var(--text-light);
    font-size: 14px;
    font-family: inherit;
    outline: none;
    resize: none;
  }
  
  .prayer-inscription::placeholder {
    color: var(--text-scripture);
    font-style: italic;
  }
  
  .altar-tools {
    display: flex;
    gap: 12px;
  }
  
  .altar-tool {
    background: none;
    border: none;
    color: var(--border-gold-strong);
    font-size: 20px;
    cursor: pointer;
    padding: 5px;
    transition: all 0.3s;
  }
  
  .altar-tool:hover {
    color: var(--text-divine);
    transform: scale(1.2);
    filter: drop-shadow(0 0 10px currentColor);
  }
  
  .send-prayer {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    padding: 8px 16px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 5px;
  }
  
  .send-prayer:hover {
    background: linear-gradient(135deg, var(--primary-gold-light), #ffc947);
    box-shadow: var(--shadow-divine-strong);
  }
  
  .send-icon {
    font-size: 16px;
  }
  
  @media (max-width: 768px) {
    .sanctuary-container {
      flex-direction: column;
      height: 100vh;
      height: 100dvh;
    }
    
    .sidebar {
      display: none;
    }
    
    .chamber-selection {
      padding: 0 10px;
      gap: 1px;
    }
    
    .chamber-portal {
      padding: 8px 12px;
      font-size: 12px;
    }
    
    .chamber-icon {
      font-size: 14px;
    }
    
    .chamber-name {
      display: none;
    }
    
    .chamber-portal.active .chamber-name {
      display: inline;
    }
    
    .chat-container {
      width: 100%;
      height: 100vh;
      height: 100dvh;
    }
    
    .chat-header {
      padding: 15px;
    }
    
    .chat-title {
      font-size: 1.2rem;
    }
    
    .chat-subtitle {
      font-size: 0.8rem;
    }
    
    .messages-scroll {
      height: calc(100vh - 180px);
      height: calc(100dvh - 180px);
      padding: 10px;
    }
    
    .message {
      padding: 10px;
      margin: 5px;
      max-width: 85%;
    }
    
    .message-header {
      font-size: 0.75rem;
    }
    
    .message-body {
      font-size: 0.9rem;
    }
    
    .altar-ground {
      padding: 10px;
    }
    
    .prayer-vessel {
      gap: 8px;
    }
    
    .prayer-inscription {
      padding: 10px 12px;
      font-size: 16px;
      border-radius: 20px;
    }
    
    .prayer-inscription::placeholder {
      font-size: 0.85rem;
    }
    
    .altar-tools {
      display: none;
    }
    
    .send-prayer {
      padding: 10px 16px;
      font-size: 0.9rem;
      border-radius: 20px;
    }
    
    .divine-verse {
      display: none;
    }
    
    .exit-sanctuary {
      top: 15px;
      right: 15px;
      padding: 8px 14px;
      font-size: 0.85rem;
    }
  }
  
  @media (max-width: 480px) {
    .chat-header {
      padding: 12px;
    }
    
    .chat-title {
      font-size: 1.1rem;
    }
    
    .messages-scroll {
      padding: 8px;
    }
    
    .message {
      padding: 8px;
      margin: 4px;
    }
    
    .message-header {
      font-size: 0.7rem;
    }
    
    .message-body {
      font-size: 0.85rem;
    }
    
    .prayer-inscription {
      font-size: 16px;
      padding: 8px 10px;
    }
    
    .send-prayer {
      padding: 8px 14px;
      font-size: 0.85rem;
    }
  }
</style>