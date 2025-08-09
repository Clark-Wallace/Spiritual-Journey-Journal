<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  import ChatRequestNotification from './ChatRequestNotification.svelte';
  
  export let isOpen = false;
  export let recipientId: string | null = null;
  export let recipientName: string = '';
  export let onAcceptChat: ((fromUserId: string, fromUserName: string) => void) | null = null;
  
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
  }
  
  let tabs: ChatTab[] = [];
  let activeTabId: string | null = null;
  let messagesContainer: HTMLDivElement;
  let pendingRequestCount = 0;
  
  // Get active tab
  $: activeTab = tabs.find(t => t.id === activeTabId);
  $: messages = activeTab?.messages || [];
  $: newMessage = activeTab?.newMessage || '';
  $: loading = activeTab?.loading || false;
  $: otherUserPresent = activeTab?.otherUserPresent || false;
  
  $: if (isOpen && recipientId && recipientName) {
    // Check if tab already exists
    const existingTab = tabs.find(t => t.id === recipientId);
    if (!existingTab) {
      // Create new tab
      const newTab: ChatTab = {
        id: recipientId,
        name: recipientName,
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
      activeTabId = recipientId;
      
      // Load messages for new tab
      loadMessagesForTab(recipientId);
      setupRealtimeSubscriptionForTab(recipientId);
      setupChatPresenceForTab(recipientId);
    } else {
      // Switch to existing tab
      activeTabId = recipientId;
    }
    checkPendingRequests();
  }
  
  onMount(() => {
    // Check for pending requests periodically while chat is open
    const interval = setInterval(() => {
      if (isOpen) checkPendingRequests();
    }, 5000);
    
    return () => clearInterval(interval);
  });
  
  onDestroy(() => {
    // Clean up all tabs
    tabs.forEach(tab => {
      if (tab.subscription) {
        tab.subscription.unsubscribe();
      }
      if (tab.presenceSubscription) {
        tab.presenceSubscription.unsubscribe();
      }
      if (tab.presenceTimeoutId) {
        clearTimeout(tab.presenceTimeoutId);
      }
      if (tab.presenceCheckTimeout) {
        clearTimeout(tab.presenceCheckTimeout);
      }
    });
    removeChatPresence();
  });
  
  async function checkPendingRequests() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Check for pending chat requests
    const { data, error } = await supabase
      .from('chat_requests')
      .select('id')
      .eq('to_user_id', user.id)
      .eq('status', 'pending')
      .gt('expires_at', new Date().toISOString());
    
    if (!error && data) {
      pendingRequestCount = data.length;
    } else {
      // If table doesn't exist, just set to 0
      pendingRequestCount = 0;
    }
  }
  
  async function loadMessagesForTab(tabId: string) {
    const tab = tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    tab.loading = true;
    tabs = tabs; // Trigger reactivity
    
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
    
    // If RPC function has errors or doesn't exist, use direct query
    if (error && (error.message?.includes('function') || error?.code === '42883' || error?.code === '42702')) {
      console.log('RPC function error, using direct query:', error);
      
      // Direct query fallback - get messages between the two users
      const result = await supabase
        .from('private_messages')
        .select(`
          id,
          from_user_id,
          to_user_id,
          message,
          is_read,
          created_at
        `)
        .or(`and(from_user_id.eq.${user.id},to_user_id.eq.${recipientId}),and(from_user_id.eq.${recipientId},to_user_id.eq.${user.id})`)
        .order('created_at', { ascending: false })
        .limit(50);
      
      if (!result.error && result.data) {
        // Transform data to match RPC function format
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
        
        // Mark messages as read
        await supabase
          .from('private_messages')
          .update({ is_read: true })
          .eq('to_user_id', user.id)
          .eq('from_user_id', recipientId)
          .eq('is_read', false);
        
        error = null;
      } else {
        error = result.error;
      }
    } else if (!error && data) {
      data = data.reverse(); // Show oldest first
    }
    
    if (!error && data) {
      messages = data;
      console.log('Messages loaded successfully:', data.length, 'messages');
      scrollToBottom();
    } else {
      console.error('Error loading messages:', error);
    }
    
    loading = false;
    console.log('Loading complete, messages:', messages.length);
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
    
    console.log('Setting up realtime subscription for private messages');
    
    subscription = supabase
      .channel(`private-messages-${user.id}-${recipientId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'private_messages'
      }, (payload) => {
        console.log('Received new private message:', payload);
        
        // Check if this message is part of our conversation
        const newMessage = payload.new;
        if ((newMessage.from_user_id === user.id && newMessage.to_user_id === recipientId) ||
            (newMessage.from_user_id === recipientId && newMessage.to_user_id === user.id)) {
          
          const newMsg = {
            message_id: newMessage.id,
            from_user_id: newMessage.from_user_id,
            from_user_name: newMessage.from_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
            to_user_id: newMessage.to_user_id,
            to_user_name: newMessage.to_user_id === user.id ? ($userInfo?.name || 'You') : recipientName,
            message: newMessage.message,
            is_read: newMessage.is_read,
            created_at: newMessage.created_at,
            is_mine: newMessage.from_user_id === user.id
          };
          
          messages = [...messages, newMsg];
          scrollToBottom();
          
          // Mark as read if it's for us
          if (newMessage.to_user_id === user.id && !newMessage.is_read) {
            markAsRead(newMessage.id);
          }
        }
      })
      .subscribe((status) => {
        console.log('Private messages subscription status:', status);
      });
  }
  
  async function markAsRead(messageId: string) {
    await supabase
      .from('private_messages')
      .update({ is_read: true })
      .eq('id', messageId);
  }
  
  async function setupChatPresence() {
    const user = await getCurrentUser();
    if (!user || !recipientId) return;
    
    // Create a unique conversation ID (sorted user IDs to ensure consistency)
    const conversationId = [user.id, recipientId].sort().join('-');
    
    console.log('Setting up chat presence for conversation:', conversationId);
    
    // Start optimistic - assume both users are present when chat opens
    otherUserPresent = true;
    hasShownJoinedMessage = false;
    
    // Set up subscription to monitor other user's presence
    presenceSubscription = supabase
      .channel(`chat-presence-${conversationId}`)
      .on('presence', { event: 'sync' }, () => {
        const state = presenceSubscription.presenceState();
        console.log('Presence sync, state keys:', Object.keys(state));
        
        // Look for the other user in the presence state
        const otherUserPresent_new = Object.keys(state).some(key => {
          const presence = state[key][0]; // Get first presence entry
          return presence && presence.user_id === recipientId;
        });
        
        console.log('Other user present:', otherUserPresent_new);
        
        // Only show left notification if they were previously present and now aren't
        if (otherUserPresent && !otherUserPresent_new && hasShownJoinedMessage) {
          // Add delay before showing left notification to avoid false positives
          presenceCheckTimeout = setTimeout(() => {
            if (!otherUserPresent && isOpen) {
              showUserLeftNotification();
            }
          }, 5000); // 5 second delay
        }
        
        otherUserPresent = otherUserPresent_new;
        if (otherUserPresent) {
          hasShownJoinedMessage = true;
          // Clear any pending "left" notification
          if (presenceCheckTimeout) {
            clearTimeout(presenceCheckTimeout);
            presenceCheckTimeout = null;
          }
        }
      })
      .on('presence', { event: 'join' }, ({ key, newPresences }) => {
        console.log('User joined presence:', key, newPresences);
        newPresences.forEach(presence => {
          if (presence.user_id === recipientId) {
            otherUserPresent = true;
            hasShownJoinedMessage = true;
            // Clear any pending "left" notification
            if (presenceCheckTimeout) {
              clearTimeout(presenceCheckTimeout);
              presenceCheckTimeout = null;
            }
          }
        });
      })
      .on('presence', { event: 'leave' }, ({ key, leftPresences }) => {
        console.log('User left presence:', key, leftPresences);
        leftPresences.forEach(presence => {
          if (presence.user_id === recipientId) {
            otherUserPresent = false;
            // Add delay before showing left notification
            if (hasShownJoinedMessage) {
              presenceCheckTimeout = setTimeout(() => {
                if (!otherUserPresent && isOpen) {
                  showUserLeftNotification();
                }
              }, 5000); // 5 second delay
            }
          }
        });
      })
      .subscribe(async (status) => {
        console.log('Chat presence subscription status:', status);
        if (status === 'SUBSCRIBED') {
          await presenceSubscription.track({
            user_id: user.id,
            conversation_id: conversationId,
            online_at: new Date().toISOString(),
          });
          
          // Start heartbeat
          updateChatPresence(conversationId);
        }
      });
  }
  
  async function updateChatPresence(conversationId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Heartbeat to show we're still active
    if (presenceSubscription) {
      await presenceSubscription.track({
        user_id: user.id,
        conversation_id: conversationId,
        online_at: new Date().toISOString(),
      });
    }
    
    // Schedule next heartbeat
    presenceTimeoutId = setTimeout(() => {
      if (isOpen && recipientId) {
        updateChatPresence(conversationId);
      }
    }, 10000); // Update every 10 seconds
  }
  
  async function removeChatPresence() {
    if (presenceSubscription) {
      await presenceSubscription.untrack();
    }
  }
  
  function showUserLeftNotification() {
    // Only show the notification once per chat session
    // Check if we already have a "left" system message
    const hasLeftMessage = messages.some(msg => 
      msg.is_system && msg.message.includes('has left the conversation')
    );
    
    if (hasLeftMessage) return;
    
    // Add a system message to the chat
    const systemMessage = {
      message_id: `system-${Date.now()}`,
      from_user_id: null,
      from_user_name: 'System',
      to_user_id: null,
      to_user_name: '',
      message: `${recipientName} has left the conversation`,
      is_read: true,
      created_at: new Date().toISOString(),
      is_mine: false,
      is_system: true
    };
    
    console.log('Showing user left notification for:', recipientName);
    messages = [...messages, systemMessage];
    scrollToBottom();
  }
  
  function scrollToBottom() {
    setTimeout(() => {
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }, 100);
  }
  
  function close() {
    removeChatPresence();
    isOpen = false;
    recipientId = null;
    recipientName = '';
    messages = [];
    otherUserPresent = true;
    hasShownJoinedMessage = false;
    if (subscription) {
      subscription.unsubscribe();
      subscription = null;
    }
    if (presenceSubscription) {
      presenceSubscription.unsubscribe();
      presenceSubscription = null;
    }
    if (presenceTimeoutId) {
      clearTimeout(presenceTimeoutId);
      presenceTimeoutId = null;
    }
    if (presenceCheckTimeout) {
      clearTimeout(presenceCheckTimeout);
      presenceCheckTimeout = null;
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

  // Handle accepting a new chat request while in current chat
  function handleAcceptNewChat(fromUserId: string, fromUserName: string) {
    // Option 1: Switch to the new chat
    // Close current chat and open new one
    close();
    if (onAcceptChat) {
      onAcceptChat(fromUserId, fromUserName);
    }
    
    // Option 2: Could instead show a notification that new chat is waiting
    // and let user decide when to switch
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
      <div class="dm-header">
        <h3>💬 Private Message with {recipientName}</h3>
        <div class="header-right">
          {#if pendingRequestCount > 0}
            <div class="pending-requests-indicator">
              <span class="request-icon">👋</span>
              <span class="request-count">{pendingRequestCount} new {pendingRequestCount === 1 ? 'request' : 'requests'}</span>
            </div>
          {/if}
          <div class="chat-status">
            <span class="presence-indicator {otherUserPresent ? 'online' : 'offline'}"></span>
            <span class="status-text">{otherUserPresent ? 'Online' : 'Offline'}</span>
          </div>
          <button class="close-btn" on:click={close}>✕</button>
        </div>
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
    gap: 1rem;
  }
  
  .dm-header h3 {
    margin: 0;
    color: var(--text-divine);
    font-size: 1.2rem;
    flex: 1;
  }
  
  .header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  
  .pending-requests-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: linear-gradient(135deg, #ff6b6b, #ff8787);
    padding: 0.4rem 0.8rem;
    border-radius: 20px;
    animation: pulse 2s infinite;
  }
  
  .request-icon {
    font-size: 1.1rem;
    animation: wave 1s infinite;
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
  
  .request-count {
    color: white;
    font-size: 0.85rem;
    font-weight: 600;
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
    
    .dm-header {
      flex-wrap: wrap;
      padding: 0.75rem 1rem;
    }
    
    .dm-header h3 {
      font-size: 1rem;
      width: 100%;
      margin-bottom: 0.5rem;
    }
    
    .header-right {
      width: 100%;
      justify-content: space-between;
    }
    
    .pending-requests-indicator {
      padding: 0.3rem 0.6rem;
      font-size: 0.85rem;
    }
    
    .request-count {
      font-size: 0.75rem;
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