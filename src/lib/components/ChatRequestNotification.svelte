<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore } from '../stores/auth';
  
  export let onAcceptChat: (fromUserId: string, fromUserName: string) => void;
  export let onChatRequestAccepted: ((userId: string, userName: string) => void) | null = null;
  
  let pendingRequests: any[] = [];
  let subscription: any;
  let checkInterval: any;
  
  onMount(() => {
    loadPendingRequests();
    setupRealtimeSubscription();
    
    // Check for expired requests every 5 seconds
    checkInterval = setInterval(() => {
      loadPendingRequests();
    }, 5000);
  });
  
  onDestroy(() => {
    if (subscription) {
      subscription.unsubscribe();
    }
    if (checkInterval) {
      clearInterval(checkInterval);
    }
  });
  
  async function loadPendingRequests() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Try RPC function first, fallback to direct query
    let { data, error } = await supabase
      .rpc('get_pending_chat_requests', { p_user_id: user.id });
    
    // If RPC function doesn't exist, use direct query
    if (error && (error.message?.includes('function') || error?.code === '42883')) {
      console.log('Chat requests RPC not found, using direct query');
      
      const directResult = await supabase
        .from('chat_requests')
        .select('id, from_user_id, from_user_name, created_at, expires_at')
        .eq('to_user_id', user.id)
        .eq('status', 'pending')
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false });
      
      if (!directResult.error && directResult.data) {
        pendingRequests = directResult.data.map(req => ({
          request_id: req.id,
          from_user_id: req.from_user_id,
          from_user_name: req.from_user_name,
          created_at: req.created_at,
          expires_at: req.expires_at
        }));
      } else if (directResult.error && !directResult.error.message?.includes('does not exist')) {
        console.error('Error loading chat requests:', directResult.error);
      }
      // If table doesn't exist, just silently fail (no requests to show)
    } else if (!error && data) {
      pendingRequests = data;
    } else if (error) {
      console.error('Error loading chat requests:', error);
    }
  }
  
  function setupRealtimeSubscription() {
    const user = $authStore;
    if (!user) return;
    
    subscription = supabase
      .channel(`chat-requests-${user.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'chat_requests',
        filter: `to_user_id=eq.${user.id}`
      }, (payload) => {
        // New request received
        loadPendingRequests();
      })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'chat_requests',
        filter: `from_user_id=eq.${user.id}`
      }, (payload) => {
        // Response to our request
        if (payload.new.status === 'accepted') {
          // Get the user info who accepted our request
          const toUserId = payload.new.to_user_id;
          // We need to get the actual name - for now use a generic name
          // In a real app, this would need a user lookup
          const toUserName = 'User'; // TODO: Look up actual user name
          
          // Notify the parent component to open chat
          if (onChatRequestAccepted) {
            onChatRequestAccepted(toUserId, toUserName);
          }
        } else if (payload.new.status === 'declined') {
          showTemporaryMessage(`${getRecipientName(payload.new.to_user_id)} is not available right now.`);
        } else if (payload.new.status === 'timeout') {
          showTemporaryMessage(`${getRecipientName(payload.new.to_user_id)} is busy.`);
        }
      })
      .subscribe();
  }
  
  async function respondToRequest(requestId: string, response: 'accepted' | 'declined') {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Remove from pending immediately to prevent duplicate actions
    const request = pendingRequests.find(r => r.request_id === requestId);
    console.log('Responding to chat request:', { requestId, response, request });
    pendingRequests = pendingRequests.filter(r => r.request_id !== requestId);
    
    // Try RPC function first, fallback to direct update
    let { data, error } = await supabase
      .rpc('respond_to_chat_request', {
        p_request_id: requestId,
        p_user_id: user.id,
        p_response: response
      });
    
    // If RPC function doesn't exist, use direct update
    if (error && (error.message?.includes('function') || error?.code === '42883')) {
      console.log('RPC function not found, using direct update');
      
      const updateResult = await supabase
        .from('chat_requests')
        .update({ 
          status: response, 
          responded_at: new Date().toISOString() 
        })
        .eq('id', requestId)
        .eq('to_user_id', user.id)
        .select('from_user_id')
        .single();
      
      if (!updateResult.error && updateResult.data) {
        // Handle the response
        if (response === 'accepted' && request) {
          onAcceptChat(request.from_user_id, request.from_user_name);
        }
      } else if (updateResult.error && !updateResult.error.message?.includes('does not exist')) {
        console.error('Error responding to chat request:', updateResult.error);
      }
      // If table doesn't exist, just remove from local state
      else {
        pendingRequests = pendingRequests.filter(r => r.request_id !== requestId);
      }
    } else if (!error && data && data[0]) {
      const result = data[0];
      if (result.success) {
        if (response === 'accepted' && request) {
          // We already have the request from before we removed it
          onAcceptChat(request.from_user_id, request.from_user_name);
        }
      }
    } else if (error) {
      console.error('Error responding to chat request:', error);
    }
  }
  
  function getRecipientName(userId: string): string {
    // Try to find the user name from presence data (if available from parent)
    // For now, return a generic name - this could be enhanced with a user lookup
    return 'User';
  }
  
  function showTemporaryMessage(message: string) {
    // Create a temporary notification
    const notification = document.createElement('div');
    notification.className = 'chat-status-message';
    notification.textContent = message;
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      background: linear-gradient(135deg, #ff6b6b, #ee5a24);
      color: white;
      padding: 1rem 1.5rem;
      border-radius: 10px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
      z-index: 3000;
      animation: slideInRight 0.3s ease-out;
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
      notification.style.animation = 'slideOutRight 0.3s ease-in';
      setTimeout(() => {
        document.body.removeChild(notification);
      }, 300);
    }, 3000);
  }
  
  function getTimeRemaining(expiresAt: string): string {
    const remaining = Math.max(0, Math.floor((new Date(expiresAt).getTime() - Date.now()) / 1000));
    return `${remaining}s`;
  }
</script>

<!-- Chat Request Notifications -->
{#each pendingRequests as request}
  <div class="chat-request-notification">
    <div class="request-content">
      <div class="request-avatar">
        {request.from_user_name?.slice(0, 2).toUpperCase()}
      </div>
      <div class="request-details">
        <div class="request-message">
          <strong>{request.from_user_name}</strong> would like to chat
        </div>
        <div class="request-timer">
          Expires in {getTimeRemaining(request.expires_at)}
        </div>
      </div>
    </div>
    <div class="request-actions">
      <button 
        class="accept-btn"
        on:click={() => respondToRequest(request.request_id, 'accepted')}
      >
        💬 Accept
      </button>
      <button 
        class="decline-btn"
        on:click={() => respondToRequest(request.request_id, 'declined')}
      >
        ✕ Not now
      </button>
    </div>
  </div>
{/each}

<style>
  .chat-request-notification {
    position: fixed;
    top: 20px;
    right: 20px;
    background: linear-gradient(135deg, #1a1a2e, #0f0f1e);
    border: 2px solid var(--border-gold);
    border-radius: 15px;
    padding: 1.5rem;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.8),
                0 0 40px rgba(255, 215, 0, 0.2);
    z-index: 2500;
    min-width: 320px;
    animation: slideInRight 0.3s ease-out;
  }
  
  @keyframes slideInRight {
    from {
      transform: translateX(100%);
      opacity: 0;
    }
    to {
      transform: translateX(0);
      opacity: 1;
    }
  }
  
  @keyframes slideOutRight {
    from {
      transform: translateX(0);
      opacity: 1;
    }
    to {
      transform: translateX(100%);
      opacity: 0;
    }
  }
  
  .request-content {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .request-avatar {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 1.2rem;
  }
  
  .request-details {
    flex: 1;
  }
  
  .request-message {
    color: var(--text-divine);
    font-size: 1.1rem;
    margin-bottom: 0.25rem;
  }
  
  .request-timer {
    color: var(--text-scripture);
    font-size: 0.85rem;
    opacity: 0.8;
  }
  
  .request-actions {
    display: flex;
    gap: 0.75rem;
  }
  
  .accept-btn {
    flex: 1;
    padding: 0.75rem 1rem;
    background: linear-gradient(135deg, #4caf50, #45a049);
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    transition: all 0.2s;
  }
  
  .accept-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(76, 175, 80, 0.3);
  }
  
  .decline-btn {
    flex: 1;
    padding: 0.75rem 1rem;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
    color: var(--text-scripture);
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .decline-btn:hover {
    background: rgba(255, 255, 255, 0.15);
    border-color: rgba(255, 255, 255, 0.3);
  }
  
  /* Mobile responsive */
  @media (max-width: 768px) {
    .chat-request-notification {
      top: 10px;
      right: 10px;
      left: 10px;
      min-width: unset;
    }
    
    .request-content {
      gap: 0.75rem;
    }
    
    .request-avatar {
      width: 40px;
      height: 40px;
      font-size: 1rem;
    }
    
    .request-message {
      font-size: 1rem;
    }
  }
</style>