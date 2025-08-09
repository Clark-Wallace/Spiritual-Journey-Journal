<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  import ChatRequestNotification from './ChatRequestNotification.svelte';
  
  export let isOpen = false;
  export let recipientId: string | null = null;
  export let recipientName: string = '';
  export let onAcceptChat: ((fromUserId: string, fromUserName: string) => void) | null = null;
  export let onCounselStatusChange: ((usersInCounsel: string[]) => void) | null = null;
  
  // Tab management
  interface ChatTab {
    id: string;
    name: string;
    messages: any[];
    newMessage: string;
    loading: boolean;
    subscription: any;
    presenceSubscription: any;
    otherUserPresent: boolean;
    presenceTimeoutId: any;
    presenceCheckTimeout: any;
    hasShownJoinedMessage: boolean;
    unreadCount: number;
    messagesContainer?: HTMLDivElement;
  }
  
  let tabs: ChatTab[] = [];
  let activeTabId: string | null = null;
  let pendingRequestCount = 0;
  
  // Get active tab
  $: activeTab = tabs.find(t => t.id === activeTabId);
  
  // Notify parent about users in counsel
  $: if (onCounselStatusChange) {
    const activeUserIds = tabs.map(tab => tab.id);
    onCounselStatusChange(activeUserIds);
  }
  
  // Open new chat or switch to existing
  $: if (isOpen && recipientId && recipientName) {
    openOrSwitchToChat(recipientId, recipientName);
  }
  
  onMount(() => {
    // Check for pending requests periodically
    const interval = setInterval(() => {
      if (isOpen) checkPendingRequests();
    }, 5000);
    
    // Update presence for all active chats
    const presenceInterval = setInterval(() => {
      tabs.forEach(tab => {
        if (tab.id) updateChatPresenceForTab(tab.id);
      });
    }, 10000);
    
    return () => {
      clearInterval(interval);
      clearInterval(presenceInterval);
    };
  });
  
  onDestroy(() => {
    // Clean up all tabs
    tabs.forEach(tab => cleanupTab(tab));
  });
  
  function openOrSwitchToChat(userId: string, userName: string) {
    const existingTab = tabs.find(t => t.id === userId);
    
    if (existingTab) {
      // Switch to existing tab and reset unread count
      activeTabId = userId;
      existingTab.unreadCount = 0;
      tabs = tabs;
    } else {
      // Create new tab
      const newTab: ChatTab = {
        id: userId,
        name: userName,
        messages: [],
        newMessage: '',
        loading: false,
        subscription: null,
        presenceSubscription: null,
        otherUserPresent: true,
        presenceTimeoutId: null,
        presenceCheckTimeout: null,
        hasShownJoinedMessage: false,
        unreadCount: 0
      };
      
      tabs = [...tabs, newTab];
      activeTabId = userId;
      
      // Initialize tab
      loadMessagesForTab(userId);
      setupRealtimeSubscriptionForTab(userId);
      setupChatPresenceForTab(userId);
    }
    
    checkPendingRequests();
  }
  
  function cleanupTab(tab: ChatTab) {
    if (tab.subscription) tab.subscription.unsubscribe();
    if (tab.presenceSubscription) {
      tab.presenceSubscription.untrack();
      tab.presenceSubscription.unsubscribe();
    }
    if (tab.presenceTimeoutId) clearTimeout(tab.presenceTimeoutId);
    if (tab.presenceCheckTimeout) clearTimeout(tab.presenceCheckTimeout);
  }
  
  function closeTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (tab) {
      cleanupTab(tab);
      tabs = tabs.filter(t => t.id !== tabId);
      
      // If closing active tab, switch to another
      if (activeTabId === tabId) {
        activeTabId = tabs.length > 0 ? tabs[0].id : null;
      }
      
      // If no tabs left, close the modal
      if (tabs.length === 0) {
        close();
      }
    }
  }
  
  async function checkPendingRequests() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('chat_requests')
      .select('id')
      .eq('to_user_id', user.id)
      .eq('status', 'pending')
      .gt('expires_at', new Date().toISOString());
    
    pendingRequestCount = (!error && data) ? data.length : 0;
  }
  
  async function loadMessagesForTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    tab.loading = true;
    tabs = tabs;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    // Try RPC function first, fallback to direct query
    let { data, error } = await supabase
      .rpc('get_conversation_messages', {
        p_user_id: user.id,
        p_other_user_id: tabId,
        p_limit: 50,
        p_offset: 0
      });
    
    // Fallback to direct query if RPC fails
    if (error && (error.message?.includes('function') || error?.code === '42883' || error?.code === '42702')) {
      const result = await supabase
        .from('private_messages')
        .select('*')
        .or(`and(from_user_id.eq.${user.id},to_user_id.eq.${tabId}),and(from_user_id.eq.${tabId},to_user_id.eq.${user.id})`)
        .order('created_at', { ascending: false })
        .limit(50);
      
      if (!result.error && result.data) {
        data = result.data.map(msg => ({
          message_id: msg.id,
          from_user_id: msg.from_user_id,
          from_user_name: msg.from_user_id === user.id ? ($userInfo?.name || 'You') : tab.name,
          to_user_id: msg.to_user_id,
          to_user_name: msg.to_user_id === user.id ? ($userInfo?.name || 'You') : tab.name,
          message: msg.message,
          is_read: msg.is_read,
          created_at: msg.created_at,
          is_mine: msg.from_user_id === user.id
        })).reverse();
        
        // Mark as read
        await supabase
          .from('private_messages')
          .update({ is_read: true })
          .eq('to_user_id', user.id)
          .eq('from_user_id', tabId)
          .eq('is_read', false);
      }
    } else if (data) {
      data = data.reverse();
    }
    
    if (data) {
      tab.messages = data;
      tab.loading = false;
      tabs = tabs;
      scrollToBottomForTab(tabId);
    }
  }
  
  async function sendMessage() {
    if (!activeTab || !activeTab.newMessage.trim()) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('private_messages')
      .insert({
        from_user_id: user.id,
        to_user_id: activeTab.id,
        message: activeTab.newMessage.trim()
      });
    
    if (!error) {
      activeTab.newMessage = '';
      tabs = tabs;
    }
  }
  
  function setupRealtimeSubscriptionForTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    const user = $authStore;
    if (!user) return;
    
    if (tab.subscription) {
      tab.subscription.unsubscribe();
    }
    
    tab.subscription = supabase
      .channel(`private-messages-${user.id}-${tabId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'private_messages'
      }, (payload) => {
        const newMessage = payload.new;
        if ((newMessage.from_user_id === user.id && newMessage.to_user_id === tabId) ||
            (newMessage.from_user_id === tabId && newMessage.to_user_id === user.id)) {
          
          const newMsg = {
            message_id: newMessage.id,
            from_user_id: newMessage.from_user_id,
            from_user_name: newMessage.from_user_id === user.id ? ($userInfo?.name || 'You') : tab.name,
            to_user_id: newMessage.to_user_id,
            to_user_name: newMessage.to_user_id === user.id ? ($userInfo?.name || 'You') : tab.name,
            message: newMessage.message,
            is_read: newMessage.is_read,
            created_at: newMessage.created_at,
            is_mine: newMessage.from_user_id === user.id
          };
          
          tab.messages = [...tab.messages, newMsg];
          
          // Increment unread count if not active tab
          if (activeTabId !== tabId && newMessage.from_user_id !== user.id) {
            tab.unreadCount++;
          }
          
          tabs = tabs;
          scrollToBottomForTab(tabId);
          
          // Mark as read if active
          if (activeTabId === tabId && newMessage.to_user_id === user.id && !newMessage.is_read) {
            markAsRead(newMessage.id);
          }
        }
      })
      .subscribe();
  }
  
  async function setupChatPresenceForTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const conversationId = [user.id, tabId].sort().join('-');
    
    tab.otherUserPresent = true;
    tab.hasShownJoinedMessage = false;
    
    tab.presenceSubscription = supabase
      .channel(`chat-presence-${conversationId}`)
      .on('presence', { event: 'sync' }, () => {
        const state = tab.presenceSubscription.presenceState();
        const otherUserPresent_new = Object.keys(state).some(key => {
          const presence = state[key][0];
          return presence && presence.user_id === tabId;
        });
        
        if (tab.otherUserPresent && !otherUserPresent_new && tab.hasShownJoinedMessage) {
          tab.presenceCheckTimeout = setTimeout(() => {
            if (!tab.otherUserPresent && activeTabId === tabId) {
              showUserLeftNotification(tabId);
            }
          }, 5000);
        }
        
        tab.otherUserPresent = otherUserPresent_new;
        if (tab.otherUserPresent) {
          tab.hasShownJoinedMessage = true;
          if (tab.presenceCheckTimeout) {
            clearTimeout(tab.presenceCheckTimeout);
            tab.presenceCheckTimeout = null;
          }
        }
        tabs = tabs;
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await tab.presenceSubscription.track({
            user_id: user.id,
            conversation_id: conversationId,
            online_at: new Date().toISOString(),
          });
        }
      });
  }
  
  async function updateChatPresenceForTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab || !tab.presenceSubscription) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const conversationId = [user.id, tabId].sort().join('-');
    
    await tab.presenceSubscription.track({
      user_id: user.id,
      conversation_id: conversationId,
      online_at: new Date().toISOString(),
    });
  }
  
  function showUserLeftNotification(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    const hasLeftMessage = tab.messages.some(msg => 
      msg.is_system && msg.message.includes('has left the conversation')
    );
    
    if (hasLeftMessage) return;
    
    const systemMessage = {
      message_id: `system-${Date.now()}`,
      from_user_id: null,
      from_user_name: 'System',
      to_user_id: null,
      to_user_name: '',
      message: `${tab.name} has left the conversation`,
      is_read: true,
      created_at: new Date().toISOString(),
      is_mine: false,
      is_system: true
    };
    
    tab.messages = [...tab.messages, systemMessage];
    tabs = tabs;
    scrollToBottomForTab(tabId);
  }
  
  async function markAsRead(messageId: string) {
    await supabase
      .from('private_messages')
      .update({ is_read: true })
      .eq('id', messageId);
  }
  
  function scrollToBottomForTab(tabId: string) {
    setTimeout(() => {
      const tab = tabs.find(t => t.id === tabId);
      if (tab?.messagesContainer) {
        tab.messagesContainer.scrollTop = tab.messagesContainer.scrollHeight;
      }
    }, 100);
  }
  
  function close() {
    // Clean up all tabs
    tabs.forEach(tab => cleanupTab(tab));
    
    // Reset state
    tabs = [];
    activeTabId = null;
    isOpen = false;
    recipientId = null;
    recipientName = '';
  }
  
  function handleAcceptNewChat(fromUserId: string, fromUserName: string) {
    // Add new tab for accepted chat
    openOrSwitchToChat(fromUserId, fromUserName);
  }
  
  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendMessage();
    }
  }
  
  function handleInputChange(value: string) {
    if (activeTab) {
      activeTab.newMessage = value;
      tabs = tabs;
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

<!-- Chat request notifications appear even while in private chat -->
{#if isOpen}
  <ChatRequestNotification 
    onAcceptChat={handleAcceptNewChat}
    onChatRequestAccepted={null}
  />
{/if}

{#if isOpen}
  <div class="dm-overlay" on:click={close}>
    <div class="dm-container" on:click|stopPropagation>
      <!-- Tab bar -->
      <div class="dm-tabs">
        {#each tabs as tab}
          <button 
            class="dm-tab" 
            class:active={activeTabId === tab.id}
            on:click={() => { activeTabId = tab.id; tab.unreadCount = 0; tabs = tabs; }}
          >
            <span class="tab-name">{tab.name}</span>
            {#if tab.unreadCount > 0}
              <span class="unread-badge">{tab.unreadCount}</span>
            {/if}
            <button 
              class="tab-close"
              on:click|stopPropagation={() => closeTab(tab.id)}
            >
              ×
            </button>
          </button>
        {/each}
        {#if pendingRequestCount > 0}
          <div class="pending-indicator">
            <span class="request-icon">👋</span>
            <span class="request-text">{pendingRequestCount}</span>
          </div>
        {/if}
      </div>
      
      {#if activeTab}
        <div class="dm-header">
          <h3>💬 {activeTab.name}</h3>
          <div class="header-right">
            <div class="chat-status">
              <span class="presence-indicator {activeTab.otherUserPresent ? 'online' : 'offline'}"></span>
              <span class="status-text">{activeTab.otherUserPresent ? 'Online' : 'Offline'}</span>
            </div>
            <button class="close-btn" on:click={close}>✕</button>
          </div>
        </div>
        
        <div class="dm-messages" bind:this={activeTab.messagesContainer}>
          {#if activeTab.loading}
            <div class="loading">Loading messages...</div>
          {:else if activeTab.messages.length === 0}
            <div class="no-messages">
              <p>No messages yet</p>
              <p>Send a message to start the conversation!</p>
            </div>
          {:else}
            {#each activeTab.messages as message}
              {#if message.is_system}
                <div class="system-message">
                  <div class="system-text">{message.message}</div>
                  <div class="system-time">{formatTime(message.created_at)}</div>
                </div>
              {:else}
                <div class="dm-message {message.is_mine ? 'mine' : 'theirs'}">
                  <div class="message-bubble">
                    <div class="message-text">{message.message}</div>
                    <div class="message-time">{formatTime(message.created_at)}</div>
                  </div>
                </div>
              {/if}
            {/each}
          {/if}
        </div>
        
        <div class="dm-input">
          <input
            type="text"
            value={activeTab.newMessage}
            on:input={(e) => handleInputChange(e.target.value)}
            placeholder="Type your message..."
            on:keydown={handleKeydown}
            class="message-input"
          />
          <button 
            class="send-btn"
            on:click={sendMessage}
            disabled={!activeTab.newMessage.trim()}
          >
            Send
          </button>
        </div>
      {:else}
        <div class="no-active-chat">
          <p>No active conversation</p>
        </div>
      {/if}
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
    max-width: 600px;
    height: 700px;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.8),
                0 0 40px rgba(255, 215, 0, 0.2);
  }
  
  .dm-tabs {
    display: flex;
    gap: 0.5rem;
    padding: 0.75rem;
    background: rgba(0, 0, 0, 0.3);
    border-bottom: 1px solid var(--border-gold);
    overflow-x: auto;
    align-items: center;
  }
  
  .dm-tab {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 20px;
    color: var(--text-scripture);
    cursor: pointer;
    transition: all 0.2s;
    white-space: nowrap;
    min-width: 0;
  }
  
  .dm-tab:hover {
    background: rgba(255, 215, 0, 0.2);
    border-color: var(--border-gold);
  }
  
  .dm-tab.active {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.3), rgba(255, 193, 7, 0.2));
    border-color: var(--border-gold);
    color: var(--text-divine);
  }
  
  .tab-name {
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  
  .unread-badge {
    background: #ff4444;
    color: white;
    padding: 0.1rem 0.4rem;
    border-radius: 10px;
    font-size: 0.75rem;
    font-weight: bold;
  }
  
  .tab-close {
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    opacity: 0.6;
    transition: opacity 0.2s;
  }
  
  .tab-close:hover {
    opacity: 1;
    color: var(--text-divine);
  }
  
  .pending-indicator {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 0.3rem;
    background: linear-gradient(135deg, #ff6b6b, #ff8787);
    padding: 0.3rem 0.6rem;
    border-radius: 15px;
    animation: pulse 2s infinite;
  }
  
  .request-icon {
    animation: wave 1s infinite;
  }
  
  .request-text {
    color: white;
    font-size: 0.85rem;
    font-weight: 600;
  }
  
  @keyframes wave {
    0%, 100% { transform: rotate(0deg); }
    25% { transform: rotate(-10deg); }
    75% { transform: rotate(10deg); }
  }
  
  @keyframes pulse {
    0% {
      box-shadow: 0 0 0 0 rgba(255, 107, 107, 0.7);
    }
    70% {
      box-shadow: 0 0 0 10px rgba(255, 107, 107, 0);
    }
    100% {
      box-shadow: 0 0 0 0 rgba(255, 107, 107, 0);
    }
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
  
  .header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  
  .chat-status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.85rem;
  }
  
  .presence-indicator {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
  }
  
  .presence-indicator.online {
    background: #4caf50;
    box-shadow: 0 0 8px rgba(76, 175, 80, 0.6);
  }
  
  .presence-indicator.offline {
    background: #757575;
  }
  
  .status-text {
    color: var(--text-scripture);
    font-weight: 500;
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
  
  .loading, .no-messages, .no-active-chat {
    text-align: center;
    color: var(--text-scripture);
    padding: 2rem;
  }
  
  .no-messages p, .no-active-chat p {
    margin: 0.5rem 0;
  }
  
  .system-message {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin: 1rem 0;
  }
  
  .system-text {
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-scripture);
    padding: 0.5rem 1rem;
    border-radius: 15px;
    font-size: 0.85rem;
    font-style: italic;
    text-align: center;
  }
  
  .system-time {
    font-size: 0.7rem;
    color: var(--text-scripture);
    opacity: 0.6;
    margin-top: 0.25rem;
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
    
    .dm-tabs {
      padding: 0.5rem;
      flex-wrap: nowrap;
    }
    
    .dm-tab {
      padding: 0.4rem 0.8rem;
      font-size: 0.9rem;
    }
    
    .tab-name {
      max-width: 80px;
    }
    
    .dm-header {
      padding: 0.75rem 1rem;
    }
    
    .dm-header h3 {
      font-size: 1rem;
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
  
  .dm-tabs::-webkit-scrollbar {
    height: 4px;
  }
  
  .dm-tabs::-webkit-scrollbar-track {
    background: transparent;
  }
  
  .dm-tabs::-webkit-scrollbar-thumb {
    background: var(--border-gold);
    border-radius: 2px;
  }
</style>