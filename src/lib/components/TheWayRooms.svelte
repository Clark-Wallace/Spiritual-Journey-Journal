<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  import { currentView } from '../stores';
  import type { RealtimeChannel } from '@supabase/supabase-js';
  
  interface ChatMessage {
    id: string;
    room: string;
    user_id: string;
    user_name: string;
    content: string;
    created_at: string;
  }
  
  interface ChatRoom {
    id: string;
    name: string;
    description: string;
    icon: string;
    color: string;
  }
  
  const rooms: ChatRoom[] = [
    { id: 'prayer-room', name: 'Prayer Chamber', description: 'Lift up prayers together in unity', icon: '🙏', color: 'linear-gradient(135deg, rgba(138, 43, 226, 0.15), rgba(255, 215, 0, 0.1))' },
    { id: 'bible-study', name: 'Scripture Hall', description: 'Study the Word in fellowship', icon: '📖', color: 'linear-gradient(135deg, rgba(30, 144, 255, 0.15), rgba(255, 215, 0, 0.1))' },
    { id: 'fellowship', name: 'Gathering Place', description: 'Share in divine fellowship', icon: '⛪', color: 'linear-gradient(135deg, rgba(255, 215, 0, 0.15), rgba(255, 193, 7, 0.1))' },
    { id: 'testimony', name: 'Witness Stand', description: 'Testify of His goodness', icon: '✨', color: 'linear-gradient(135deg, rgba(76, 175, 80, 0.15), rgba(255, 215, 0, 0.1))' },
    { id: 'worship', name: 'Praise Sanctuary', description: 'Lift voices in worship', icon: '🎵', color: 'linear-gradient(135deg, rgba(255, 87, 34, 0.15), rgba(255, 215, 0, 0.1))' }
  ];
  
  let currentRoom: ChatRoom = rooms[0];
  let messages: ChatMessage[] = [];
  let newMessage = '';
  let loading = true;
  let channel: RealtimeChannel | null = null;
  let messagesContainer: HTMLElement;
  let showRoomList = false;
  
  onMount(async () => {
    await loadMessages();
    subscribeToRoom();
  });
  
  onDestroy(() => {
    if (channel) {
      supabase.removeChannel(channel);
    }
  });
  
  async function loadMessages() {
    loading = true;
    
    const { data, error } = await supabase
      .from('chat_messages')
      .select('*')
      .eq('room', currentRoom.id)
      .order('created_at', { ascending: true })
      .limit(100);
    
    if (error) {
      console.error('Error loading messages:', error);
    } else {
      messages = data || [];
    }
    
    loading = false;
    scrollToBottom();
  }
  
  function subscribeToRoom() {
    if (channel) {
      supabase.removeChannel(channel);
    }
    
    channel = supabase
      .channel(`room:${currentRoom.id}`)
      .on('postgres_changes', 
        { 
          event: 'INSERT', 
          schema: 'public', 
          table: 'chat_messages',
          filter: `room=eq.${currentRoom.id}`
        },
        (payload) => {
          messages = [...messages, payload.new as ChatMessage];
          scrollToBottom();
        }
      )
      .subscribe();
  }
  
  async function sendMessage() {
    if (!newMessage.trim()) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('chat_messages')
      .insert({
        room: currentRoom.id,
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        content: newMessage.trim()
      });
    
    if (error) {
      console.error('Error sending message:', error);
    } else {
      newMessage = '';
    }
  }
  
  function switchRoom(room: ChatRoom) {
    currentRoom = room;
    messages = [];
    showRoomList = false;
    loadMessages();
    subscribeToRoom();
  }
  
  function scrollToBottom() {
    setTimeout(() => {
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }, 100);
  }
  
  function formatTime(timestamp: string) {
    return new Date(timestamp).toLocaleTimeString('en-US', { 
      hour: 'numeric', 
      minute: '2-digit' 
    });
  }
</script>

<div class="chat-rooms-container">
  <!-- Mobile Room Toggle -->
  <div class="mobile-header">
    <button class="room-toggle" on:click={() => showRoomList = !showRoomList}>
      <span class="room-icon">{currentRoom.icon}</span>
      <span class="room-name">{currentRoom.name}</span>
      <span class="toggle-arrow">{showRoomList ? '▼' : '▶'}</span>
    </button>
    <button class="exit-mobile" on:click={() => $currentView = 'home'}>
      ✕
    </button>
  </div>
  
  <!-- Room List (Desktop Sidebar / Mobile Dropdown) -->
  <div class="rooms-sidebar" class:show-mobile={showRoomList}>
    <div class="rooms-header">
      <h3>🕊️ Chat Rooms</h3>
      <button class="exit-desktop" on:click={() => $currentView = 'home'}>
        Exit Chat
      </button>
    </div>
    
    <div class="rooms-list">
      {#each rooms as room}
        <button 
          class="room-item"
          class:active={currentRoom.id === room.id}
          style="--room-color: {room.color}"
          on:click={() => switchRoom(room)}
        >
          <span class="room-icon">{room.icon}</span>
          <div class="room-info">
            <span class="room-name">{room.name}</span>
            <span class="room-desc">{room.description}</span>
          </div>
        </button>
      {/each}
    </div>
  </div>
  
  <!-- Chat Area -->
  <div class="chat-area">
    <div class="chat-header" style="background: {currentRoom.color}">
      <div class="header-content">
        <span class="room-icon">{currentRoom.icon}</span>
        <div>
          <h2>{currentRoom.name}</h2>
          <p>{currentRoom.description}</p>
        </div>
      </div>
    </div>
    
    <div class="messages-container" bind:this={messagesContainer}>
      {#if loading}
        <div class="loading">Loading messages...</div>
      {:else if messages.length === 0}
        <div class="empty">
          <p>No messages yet. Start the conversation!</p>
        </div>
      {:else}
        {#each messages as message}
          <div class="message" class:own={message.user_id === $authStore?.id}>
            <div class="message-header">
              <span class="user-name">{message.user_name}</span>
              <span class="timestamp">{formatTime(message.created_at)}</span>
            </div>
            <div class="message-content">{message.content}</div>
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="input-area">
      <input 
        type="text"
        placeholder="Type your message..."
        bind:value={newMessage}
        on:keydown={(e) => e.key === 'Enter' && sendMessage()}
      />
      <button class="send-btn" on:click={sendMessage}>
        Send 🕊️
      </button>
    </div>
  </div>
</div>

<style>
  .chat-rooms-container {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    display: flex;
    background: linear-gradient(180deg, 
      rgba(10, 10, 15, 0.98) 0%, 
      rgba(15, 15, 25, 0.95) 50%,
      rgba(20, 15, 30, 0.98) 100%
    );
    z-index: 1000;
  }
  
  /* Divine light rays effect */
  .chat-rooms-container::before {
    content: '';
    position: absolute;
    top: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 120%;
    height: 100%;
    background: radial-gradient(
      ellipse at center top,
      rgba(255, 215, 0, 0.03) 0%,
      transparent 50%
    );
    pointer-events: none;
  }
  
  .mobile-header {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    background: linear-gradient(180deg, rgba(10, 10, 15, 0.98), rgba(15, 15, 25, 0.95));
    backdrop-filter: blur(10px);
    border-bottom: 2px solid;
    border-image: linear-gradient(90deg, transparent, rgba(255, 215, 0, 0.5), transparent) 1;
    padding: 0.75rem;
    z-index: 1002;
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.1);
  }
  
  .room-toggle {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    padding: 0.5rem;
    color: var(--text-divine);
    cursor: pointer;
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.3);
    transition: all 0.3s;
  }
  
  .room-toggle:hover {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.15), rgba(255, 193, 7, 0.08));
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.2);
  }
  
  .room-toggle .room-name {
    flex: 1;
    text-align: left;
  }
  
  .toggle-arrow {
    font-size: 0.8rem;
  }
  
  .exit-mobile, .exit-desktop {
    background: rgba(255, 67, 54, 0.2);
    border: 1px solid rgba(255, 67, 54, 0.4);
    color: #ff6b6b;
    padding: 0.5rem 1rem;
    border-radius: 6px;
    cursor: pointer;
    font-weight: 600;
    transition: all 0.3s;
  }
  
  .exit-mobile {
    padding: 0.5rem 0.75rem;
  }
  
  .exit-desktop:hover, .exit-mobile:hover {
    background: rgba(255, 67, 54, 0.3);
    transform: scale(1.05);
  }
  
  .rooms-sidebar {
    width: 250px;
    background: linear-gradient(180deg, 
      rgba(15, 15, 30, 0.98),
      rgba(20, 15, 35, 0.95)
    );
    backdrop-filter: blur(10px);
    border-right: 2px solid;
    border-image: linear-gradient(180deg, rgba(255, 215, 0, 0.3), rgba(255, 215, 0, 0.1)) 1;
    display: flex;
    flex-direction: column;
    box-shadow: 4px 0 20px rgba(255, 215, 0, 0.05);
  }
  
  .rooms-header {
    padding: 1rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.08), rgba(255, 193, 7, 0.04));
    border-bottom: 1px solid rgba(255, 215, 0, 0.3);
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  
  .rooms-header h3 {
    color: var(--text-divine);
    margin: 0;
    font-size: 1.1rem;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.5);
    font-family: var(--font-primary);
    letter-spacing: 1px;
  }
  
  .rooms-list {
    flex: 1;
    overflow-y: auto;
    padding: 0.5rem;
  }
  
  .room-item {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem;
    background: var(--room-color, rgba(255, 255, 255, 0.02));
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 8px;
    margin-bottom: 0.5rem;
    cursor: pointer;
    transition: all 0.3s;
    text-align: left;
    position: relative;
    overflow: hidden;
  }
  
  .room-item::before {
    content: '';
    position: absolute;
    top: 0;
    left: -100%;
    width: 100%;
    height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255, 215, 0, 0.1), transparent);
    transition: left 0.5s;
  }
  
  .room-item:hover::before {
    left: 100%;
  }
  
  .room-item:hover {
    border-color: var(--border-gold);
    transform: translateX(5px);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.1);
  }
  
  .room-item.active {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.15), rgba(255, 193, 7, 0.1));
    border-color: var(--border-gold);
    box-shadow: inset 0 0 30px rgba(255, 215, 0, 0.1);
  }
  
  .room-icon {
    font-size: 1.5rem;
    filter: drop-shadow(0 0 8px rgba(255, 215, 0, 0.3));
  }
  
  .room-info {
    flex: 1;
    display: flex;
    flex-direction: column;
  }
  
  .room-name {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.95rem;
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.2);
  }
  
  .room-desc {
    color: var(--text-scripture);
    font-size: 0.75rem;
    margin-top: 0.2rem;
    opacity: 0.9;
  }
  
  .chat-area {
    flex: 1;
    display: flex;
    flex-direction: column;
  }
  
  .chat-header {
    padding: 1rem;
    background: var(--room-color);
    border-bottom: 2px solid;
    border-image: linear-gradient(90deg, transparent, rgba(255, 215, 0, 0.5), transparent) 1;
    backdrop-filter: blur(10px);
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.05);
  }
  
  .header-content {
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  
  .chat-header .room-icon {
    font-size: 2rem;
  }
  
  .chat-header h2 {
    color: var(--text-divine);
    margin: 0;
    font-size: 1.3rem;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.4);
    font-family: var(--font-primary);
  }
  
  .chat-header p {
    color: var(--text-holy);
    margin: 0.2rem 0 0 0;
    font-size: 0.85rem;
    font-style: italic;
  }
  
  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    background: radial-gradient(
      ellipse at center,
      rgba(255, 215, 0, 0.01) 0%,
      transparent 70%
    );
  }
  
  .loading, .empty {
    text-align: center;
    padding: 2rem;
    color: var(--text-scripture);
  }
  
  .message {
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.03), rgba(255, 215, 0, 0.02));
    border: 1px solid rgba(255, 215, 0, 0.15);
    border-radius: 12px;
    padding: 0.75rem;
    max-width: 70%;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.2);
    backdrop-filter: blur(5px);
  }
  
  .message.own {
    align-self: flex-end;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.15), rgba(255, 215, 0, 0.08));
    border-color: rgba(138, 43, 226, 0.3);
  }
  
  .message-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
  }
  
  .user-name {
    color: var(--text-divine);
    font-weight: 600;
    font-size: 0.85rem;
    text-shadow: 0 0 8px rgba(255, 215, 0, 0.3);
  }
  
  .timestamp {
    color: var(--text-scripture);
    font-size: 0.75rem;
  }
  
  .message-content {
    color: var(--text-light);
    line-height: 1.4;
  }
  
  .input-area {
    display: flex;
    gap: 0.75rem;
    padding: 1rem;
    background: linear-gradient(180deg, rgba(15, 15, 30, 0.98), rgba(10, 10, 20, 0.95));
    border-top: 2px solid;
    border-image: linear-gradient(90deg, transparent, rgba(255, 215, 0, 0.5), transparent) 1;
    backdrop-filter: blur(10px);
    box-shadow: 0 -4px 20px rgba(255, 215, 0, 0.05);
  }
  
  .input-area input {
    flex: 1;
    padding: 0.75rem;
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.05), rgba(255, 215, 0, 0.02));
    border: 1px solid var(--border-gold);
    border-radius: 25px;
    color: var(--text-light);
    font-size: 0.95rem;
    box-shadow: inset 0 2px 5px rgba(0, 0, 0, 0.2);
    transition: all 0.3s;
  }
  
  .input-area input:focus {
    outline: none;
    border-color: var(--primary-gold);
    box-shadow: inset 0 2px 5px rgba(0, 0, 0, 0.2), 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .input-area input::placeholder {
    color: var(--text-scripture);
  }
  
  .send-btn {
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    border: none;
    border-radius: 25px;
    color: var(--bg-dark);
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
    position: relative;
    overflow: hidden;
  }
  
  .send-btn::before {
    content: '';
    position: absolute;
    top: 50%;
    left: 50%;
    width: 0;
    height: 0;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.3);
    transform: translate(-50%, -50%);
    transition: width 0.6s, height 0.6s;
  }
  
  .send-btn:hover::before {
    width: 100%;
    height: 100%;
  }
  
  .send-btn:hover {
    transform: scale(1.05);
    box-shadow: 0 0 30px rgba(255, 215, 0, 0.5);
  }
  
  /* Mobile Styles */
  @media (max-width: 768px) {
    .chat-rooms-container {
      flex-direction: column;
    }
    
    .mobile-header {
      display: flex;
      gap: 0.5rem;
    }
    
    .rooms-sidebar {
      display: none;
      position: fixed;
      top: 60px;
      left: 0;
      right: 0;
      width: 100%;
      max-height: 50vh;
      z-index: 1001;
      border-right: none;
      border-bottom: 2px solid var(--border-gold);
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
    }
    
    .rooms-sidebar.show-mobile {
      display: flex;
    }
    
    .exit-desktop {
      display: none;
    }
    
    .chat-area {
      padding-top: 60px;
    }
    
    .message {
      max-width: 85%;
    }
    
    .input-area {
      padding: 0.75rem;
    }
    
    .input-area input {
      padding: 0.6rem;
      font-size: 16px; /* Prevents zoom on iOS */
    }
    
    .send-btn {
      padding: 0.6rem 1rem;
    }
  }
  
  @media (max-width: 480px) {
    .room-toggle {
      font-size: 0.9rem;
    }
    
    .chat-header {
      padding: 0.75rem;
    }
    
    .chat-header h2 {
      font-size: 1.1rem;
    }
    
    .messages-container {
      padding: 0.75rem;
    }
    
    .message {
      padding: 0.6rem;
    }
  }
</style>