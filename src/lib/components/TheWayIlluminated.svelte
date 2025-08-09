<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  import { currentView } from '../stores';
  import VoiceRecorder from './VoiceRecorder.svelte';
  import FellowshipManager from './FellowshipManager.svelte';
  import FellowshipDebug from './FellowshipDebug.svelte';
  import ChatPopoutManager from './ChatPopoutManager.svelte';
  
  let messages: any[] = [];
  let onlineUsers: any[] = [];
  let newMessage = '';
  let loading = true;
  let messagesContainer: HTMLDivElement;
  let userStatus: 'online' | 'praying' | 'reading' | 'away' = 'online';
  let subscription: any;
  let presenceSubscription: any;
  let requestSubscription: any;
  let fellowshipSubscription: any;
  let isMobile = false;
  let showFellowshipManager = false;
  let showDebug = false; // Toggle with Ctrl+Shift+D
  let showMobileSidebar = false;
  let fellowships: Set<string> = new Set();
  let pendingRequests: Set<string> = new Set();
  let incomingRequests: Set<string> = new Set();
  let requestCount = 0;
  
  // Private messaging
  let chatPopoutManager: ChatPopoutManager;
  let usersInCounsel: Set<string> = new Set(); // Track users in private chats
  
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
    { id: 'debate', name: 'Debate Room', icon: '⚖️' }
  ];
  
  let currentRoom = rooms[0];
  
  const statusConfig = {
    online: { icon: '✨', label: 'Walking in faith', color: '#4caf50' },
    praying: { icon: '🙏', label: 'In prayer', color: '#ffa726' },
    reading: { icon: '📖', label: 'Reading Word', color: '#42a5f5' },
    away: { icon: '🕊️', label: 'Away', color: '#bdbdbd' }
  };
  
  onMount(async () => {
    // Check if mobile
    isMobile = window.innerWidth <= 768;
    window.addEventListener('resize', () => {
      isMobile = window.innerWidth <= 768;
    });
    
    // Debug mode toggle
    window.addEventListener('keydown', (e) => {
      if (e.ctrlKey && e.shiftKey && e.key === 'D') {
        showDebug = !showDebug;
      }
    });
    
    // Clean up presence when user leaves the page
    const handleBeforeUnload = () => {
      removePresence();
    };
    window.addEventListener('beforeunload', handleBeforeUnload);
    
    // Also clean up on visibility change (tab switch)
    const handleVisibilityChange = () => {
      if (document.hidden) {
        removePresence();
      } else {
        updatePresence();
      }
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    
    await loadFellowships();
    await loadFellowshipRequests();
    await loadMessages();
    await updatePresence();
    setupRealtimeSubscriptions();
    
    // Update presence more frequently (every 30 seconds)
    const presenceInterval = setInterval(updatePresence, 30000);
    
    // Clean up stale users periodically (every minute)
    const cleanupInterval = setInterval(loadOnlineUsers, 60000);
    
    return () => {
      clearInterval(presenceInterval);
      clearInterval(cleanupInterval);
      cleanupSubscriptions();
      window.removeEventListener('beforeunload', handleBeforeUnload);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  });
  
  onDestroy(async () => {
    // Clean up presence when component unmounts
    await removePresence();
    cleanupSubscriptions();
  });
  
  function setupRealtimeSubscriptions() {
    // Clean up existing subscription first
    if (subscription) {
      supabase.removeChannel(subscription);
    }
    
    subscription = supabase
      .channel(`room-${currentRoom.id}`)
      .on('postgres_changes', 
        { 
          event: 'INSERT', 
          schema: 'public', 
          table: 'chat_messages',
          filter: `room=eq.${currentRoom.id}`
        },
        (payload) => {
          console.log('New message received:', payload);
          messages = [payload.new, ...messages];
          scrollToTop();
        }
      )
      .on('postgres_changes',
        { 
          event: 'DELETE', 
          schema: 'public', 
          table: 'chat_messages',
          filter: `room=eq.${currentRoom.id}`
        },
        (payload) => {
          messages = messages.filter(m => m.id !== payload.old.id);
        }
      )
      .on('postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'chat_reactions'
        },
        (payload) => {
          console.log('Reaction change:', payload);
          updateReactionInMessages(payload);
        }
      )
      .subscribe((status) => {
        console.log('Subscription status:', status);
      });
    
    // Set up fellowship request subscription
    setupRequestSubscription();
    
    // Set up fellowship subscription
    setupFellowshipSubscription();
    
    // Clean up existing presence subscription first
    if (presenceSubscription) {
      supabase.removeChannel(presenceSubscription);
    }
    
    presenceSubscription = supabase
      .channel(`room-presence-${currentRoom.id}`)
      .on('postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'user_presence',
          filter: `current_room=eq.${currentRoom.id}`
        },
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
    if (requestSubscription) {
      supabase.removeChannel(requestSubscription);
    }
    if (fellowshipSubscription) {
      supabase.removeChannel(fellowshipSubscription);
    }
  }
  
  async function setupRequestSubscription() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Clean up existing subscription
    if (requestSubscription) {
      supabase.removeChannel(requestSubscription);
    }
    
    // Subscribe to fellowship requests for this user
    requestSubscription = supabase
      .channel('fellowship-requests-chat')
      .on('postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'fellowship_requests',
          filter: `to_user_id=eq.${user.id}`
        },
        (payload) => {
          console.log('Fellowship request change in chat:', payload);
          loadFellowshipRequests();
        }
      )
      .subscribe();
  }
  
  async function setupFellowshipSubscription() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Clean up existing subscription
    if (fellowshipSubscription) {
      supabase.removeChannel(fellowshipSubscription);
    }
    
    // Subscribe to fellowship changes for this user
    fellowshipSubscription = supabase
      .channel('fellowships-chat')
      .on('postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'fellowships',
          filter: `user_id=eq.${user.id}`
        },
        (payload) => {
          console.log('Fellowship change:', payload);
          loadFellowships();
          loadFellowshipRequests();
        }
      )
      .subscribe();
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
        ),
        message_flags (
          flag_type,
          user_id
        )
      `)
      .eq('room', currentRoom.id)
      .order('created_at', { ascending: false })
      .limit(100);
    
    if (error) {
      console.error('Error loading messages:', error);
    } else {
      // Filter out hidden messages unless they're from the current user
      const user = await getCurrentUser();
      messages = (data || []).filter(m => !m.hidden || m.user_id === user?.id);
      console.log('Loaded messages:', messages);
      setTimeout(scrollToTop, 100);
    }
    
    loading = false;
  }
  
  async function loadFellowships() {
    const user = await getCurrentUser();
    if (!user) return;
    
    console.log('Loading fellowships for user:', user.id);
    
    // Clear existing state
    fellowships.clear();
    
    const { data, error } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowships:', error);
      // Fallback: try direct table query if function doesn't exist
      const { data: fallbackData, error: fallbackError } = await supabase
        .from('fellowships')
        .select('fellow_id')
        .eq('user_id', user.id);
      
      if (!fallbackError && fallbackData) {
        fellowships = new Set(fallbackData.map((f: any) => f.fellow_id));
        console.log('Loaded fellowships (fallback):', fellowships);
      } else if (fallbackError) {
        console.error('Fallback also failed:', fallbackError);
      }
    } else if (data) {
      fellowships = new Set(data.map((f: any) => f.fellow_id));
      console.log('Loaded fellowships from RPC:', data);
      console.log('Fellowship IDs:', fellowships);
    }
    
    // Force UI update
    fellowships = new Set(fellowships);
  }
  
  async function loadFellowshipRequests() {
    const user = await getCurrentUser();
    if (!user) return;
    
    console.log('Loading fellowship requests for:', user.id);
    
    const { data, error } = await supabase
      .rpc('get_fellowship_requests', { p_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowship requests:', error);
      // Fallback: direct query
      const { data: fallbackData } = await supabase
        .from('fellowship_requests')
        .select('*')
        .or(`from_user_id.eq.${user.id},to_user_id.eq.${user.id}`)
        .eq('status', 'pending');
      
      if (fallbackData) {
        console.log('Loaded requests via fallback:', fallbackData);
        pendingRequests.clear();
        incomingRequests.clear();
        requestCount = 0;
        
        fallbackData.forEach((req: any) => {
          if (req.from_user_id === user.id) {
            pendingRequests.add(req.to_user_id);
          } else if (req.to_user_id === user.id) {
            incomingRequests.add(req.from_user_id);
            requestCount++;
          }
        });
        
        pendingRequests = new Set(pendingRequests);
        incomingRequests = new Set(incomingRequests);
      }
    } else if (data) {
      console.log('Loaded fellowship requests:', data);
      console.log('Processing requests for user:', user.id);
      pendingRequests.clear();
      incomingRequests.clear();
      requestCount = 0;
      
      data.forEach((req: any) => {
        console.log('Processing request:', {
          direction: req.direction,
          from: req.from_user_id,
          to: req.to_user_id,
          status: req.status
        });
        
        if (req.direction === 'sent') {
          pendingRequests.add(req.to_user_id);
        } else if (req.direction === 'received') {
          incomingRequests.add(req.from_user_id);
          requestCount++;
        }
      });
      
      pendingRequests = new Set(pendingRequests);
      incomingRequests = new Set(incomingRequests);
    }
    
    console.log('Final state - Request count:', requestCount, 'Incoming:', incomingRequests.size, 'Pending:', pendingRequests.size);
  }
  
  async function loadOnlineUsers() {
    // Only show users active in the last 2 minutes
    const twoMinutesAgo = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    
    // Also clean up really old presence records
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    await supabase
      .from('user_presence')
      .delete()
      .lt('last_seen', oneHourAgo);
    
    // Only load users in the current room
    const { data, error } = await supabase
      .from('user_presence')
      .select('*')
      .eq('current_room', currentRoom.id)
      .gte('last_seen', twoMinutesAgo)
      .order('last_seen', { ascending: false });
    
    if (!error) {
      onlineUsers = data || [];
      console.log(`Users in ${currentRoom.name}:`, onlineUsers.length);
    }
  }
  
  async function updatePresence() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('user_presence')
      .upsert({
        user_id: user.id,
        user_name: $userInfo?.name || user.user_metadata?.name || user.email?.split('@')[0],
        status: userStatus,
        current_room: currentRoom.id,
        last_seen: new Date().toISOString()
      }, {
        onConflict: 'user_id'
      });
    
    if (!error) {
      await loadOnlineUsers();
    }
  }
  
  async function removePresence() {
    const user = await getCurrentUser();
    if (!user) return;
    
    await supabase
      .from('user_presence')
      .delete()
      .eq('user_id', user.id);
  }
  
  async function sendMessage() {
    console.log('sendMessage called, newMessage:', newMessage);
    if (!newMessage.trim()) {
      console.log('Message is empty, returning');
      return;
    }
    
    const user = await getCurrentUser();
    if (!user) {
      console.error('No user found');
      return;
    }
    
    const userName = $userInfo?.name || user.user_metadata?.name || user.email?.split('@')[0];
    
    // Update user profile with current name
    await supabase.rpc('upsert_user_profile', {
      p_user_id: user.id,
      p_display_name: userName
    });
    
    const isPrayerRequest = newMessage.toLowerCase().includes('pray') || 
                           newMessage.toLowerCase().includes('need prayer');
    
    const messageData = {
      room: currentRoom.id,
      user_id: user.id,
      user_name: userName,
      message: newMessage.trim(),
      is_prayer_request: isPrayerRequest
    };
    
    console.log('Attempting to insert message:', messageData);
    
    const { data, error } = await supabase
      .from('chat_messages')
      .insert(messageData)
      .select()
      .single();
    
    if (error) {
      console.error('Error sending message:', error);
      alert('Failed to send message: ' + error.message);
    } else {
      console.log('Message sent successfully:', data);
      newMessage = '';
    }
  }
  
  function updateReactionInMessages(payload: any) {
    const { eventType, new: newData, old: oldData } = payload;
    const messageId = newData?.message_id || oldData?.message_id;
    
    if (!messageId) return;
    
    const messageIndex = messages.findIndex(m => m.id === messageId);
    if (messageIndex === -1) return;
    
    if (eventType === 'INSERT') {
      // Add reaction (check for duplicates first)
      if (!messages[messageIndex].chat_reactions) {
        messages[messageIndex].chat_reactions = [];
      }
      
      // Only add if it doesn't already exist (prevents duplicates from optimistic updates)
      const alreadyExists = messages[messageIndex].chat_reactions.some(
        r => r.reaction === newData.reaction && r.user_id === newData.user_id
      );
      
      if (!alreadyExists) {
        messages[messageIndex].chat_reactions.push({
          reaction: newData.reaction,
          user_id: newData.user_id
        });
      }
    } else if (eventType === 'DELETE') {
      // Remove reaction
      if (messages[messageIndex].chat_reactions) {
        messages[messageIndex].chat_reactions = messages[messageIndex].chat_reactions.filter(
          r => !(r.reaction === oldData.reaction && r.user_id === oldData.user_id)
        );
      }
    }
    
    // Trigger Svelte reactivity
    messages = messages;
  }

  async function addReaction(messageId: string, reaction: string) {
    const user = await getCurrentUser();
    if (!user) {
      console.error('No user found for adding reaction');
      return;
    }
    
    // Find the message and check if user already reacted
    const messageIndex = messages.findIndex(m => m.id === messageId);
    if (messageIndex === -1) return;
    
    const message = messages[messageIndex];
    const existingReaction = message?.chat_reactions?.find(
      r => r.reaction === reaction && r.user_id === user.id
    );
    
    if (existingReaction) {
      // Remove the reaction if it exists
      console.log('Removing reaction:', { messageId, reaction, userId: user.id });
      
      // Optimistic update - remove immediately for better UX
      messages[messageIndex].chat_reactions = message.chat_reactions.filter(
        r => !(r.reaction === reaction && r.user_id === user.id)
      );
      messages = messages; // Trigger Svelte reactivity
      
      const { error } = await supabase
        .from('chat_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .eq('reaction', reaction);
      
      if (error) {
        console.error('Error removing reaction:', error);
        // Revert optimistic update on error
        if (!messages[messageIndex].chat_reactions) {
          messages[messageIndex].chat_reactions = [];
        }
        messages[messageIndex].chat_reactions.push({
          reaction,
          user_id: user.id
        });
        messages = messages;
        return;
      }
      
      console.log('Reaction removed successfully');
    } else {
      // Add the reaction if it doesn't exist
      console.log('Adding reaction:', { messageId, reaction, userId: user.id });
      
      // Optimistic update - add immediately for better UX
      if (!messages[messageIndex].chat_reactions) {
        messages[messageIndex].chat_reactions = [];
      }
      
      // Check if it's already there (from real-time) to prevent duplicates
      const alreadyExists = messages[messageIndex].chat_reactions.some(
        r => r.reaction === reaction && r.user_id === user.id
      );
      
      if (!alreadyExists) {
        messages[messageIndex].chat_reactions.push({
          reaction,
          user_id: user.id
        });
        messages = messages; // Trigger Svelte reactivity
      }
      
      const { data, error } = await supabase
        .from('chat_reactions')
        .insert({
          message_id: messageId,
          user_id: user.id,
          reaction
        })
        .select()
        .single();
      
      if (error) {
        console.error('Error adding reaction:', error);
        // Revert optimistic update on error
        messages[messageIndex].chat_reactions = messages[messageIndex].chat_reactions.filter(
          r => !(r.reaction === reaction && r.user_id === user.id)
        );
        messages = messages;
        return;
      }
      
      console.log('Reaction added successfully:', data);
    }
  }
  
  async function flagMessage(messageId: string, flagType: 'debate_room' | 'not_the_way') {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Find the message and check if user already flagged
    const message = messages.find(m => m.id === messageId);
    const existingFlag = message?.message_flags?.find(
      f => f.flag_type === flagType && f.user_id === user.id
    );
    
    if (existingFlag) {
      // Remove the flag if it exists
      const { error } = await supabase
        .from('message_flags')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .eq('flag_type', flagType);
      
      if (error) {
        console.error('Error removing flag:', error);
      } else {
        await loadMessages();
      }
    } else {
      // Add the flag if it doesn't exist
      const { error } = await supabase
        .from('message_flags')
        .insert({
          message_id: messageId,
          user_id: user.id,
          flag_type: flagType
        });
      
      if (error) {
        console.error('Error adding flag:', error);
      } else {
        // Show appropriate feedback
        if (flagType === 'debate_room') {
          // Could show a toast: "Suggested for Debate Room"
        } else {
          // Could show a toast: "Flagged as inappropriate"
        }
        await loadMessages();
      }
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
  
  function scrollToTop() {
    if (messagesContainer) {
      messagesContainer.scrollTop = 0;
    }
  }
  
  function scrollToBottom() {
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
  }
  
  async function switchRoom(room: ChatRoom) {
    currentRoom = room;
    messages = [];
    onlineUsers = []; // Clear users list immediately for better UX
    
    // Update presence to new room
    await updatePresence();
    
    // Load messages and users for new room
    await loadMessages();
    await loadOnlineUsers();
    
    // Re-subscribe to new room (includes presence subscription)
    setupRealtimeSubscriptions();
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
    // On mobile, Enter key should send (iOS 'Done' button)
    // On desktop, Enter without Shift sends
    if (event.key === 'Enter') {
      if (isMobile || !event.shiftKey) {
        event.preventDefault();
        sendMessage();
      }
    }
  }
  
  function getInitials(name: string) {
    return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
  
  async function openPrivateMessage(userId: string, userName: string) {
    if (userId === $authStore?.id) return; // Can't DM yourself
    
    const user = await getCurrentUser();
    if (!user) return;
    
    console.log('Sending chat request to:', userName, userId);
    
    // Try RPC function first, fallback to direct insert
    let { data, error } = await supabase
      .rpc('send_chat_request', {
        p_from_user_id: user.id,
        p_to_user_id: userId,
        p_from_user_name: $userInfo?.name || user.email?.split('@')[0] || 'Anonymous'
      });
    
    // If RPC function doesn't exist, use direct approach
    if (error && (error.message?.includes('function') || error?.code === '42883')) {
      console.log('Chat request RPC not found, using direct approach');
      
      // Check if chat_requests table exists by trying to insert
      const directResult = await supabase
        .from('chat_requests')
        .insert({
          from_user_id: user.id,
          to_user_id: userId,
          from_user_name: $userInfo?.name || user.email?.split('@')[0] || 'Anonymous'
        })
        .select()
        .single();
      
      if (!directResult.error) {
        showTemporaryMessage(`Chat request sent to ${userName}`);
        return; // Success with direct insert
      } else if (directResult.error.message?.includes('does not exist')) {
        // Table doesn't exist, open chat directly (fallback to old behavior)
        console.log('Chat requests table not found, opening chat directly');
        if (chatPopoutManager) {
          chatPopoutManager.openChat(userId, userName);
        }
        return;
      } else {
        error = directResult.error;
      }
    }
    
    if (!error && data && data[0]) {
      const result = data[0];
      if (result.status === 'sent') {
        showTemporaryMessage(`Chat request sent to ${userName}`);
      } else if (result.status === 'exists') {
        showTemporaryMessage(`Chat request already pending with ${userName}`);
      }
    } else {
      console.error('Error sending chat request:', error);
      showTemporaryMessage(`Failed to send chat request - opening chat directly`);
      // Fallback to direct chat opening
      if (chatPopoutManager) {
        chatPopoutManager.openChat(userId, userName);
      }
    }
  }
  
  function acceptChatRequest(fromUserId: string, fromUserName: string) {
    console.log('Accepting chat from:', fromUserName, fromUserId);
    if (chatPopoutManager) {
      chatPopoutManager.openChat(fromUserId, fromUserName);
    }
  }
  
  // Handle when someone accepts our chat request
  function handleCounselStatusChange(userIds: string[]) {
    // Update the set of users in counsel
    usersInCounsel = new Set(userIds);
  }
  
  function handleChatRequestAccepted(userId: string, userName: string) {
    // Look up the actual user name from our online users list
    const user = onlineUsers.find(u => u.user_id === userId);
    const actualUserName = user?.user_name || userName || 'User';
    
    console.log('Our chat request was accepted by:', actualUserName);
    showTemporaryMessage(`${actualUserName} accepted your chat request`);
    // Auto-open the chat for the sender
    if (chatPopoutManager) {
      chatPopoutManager.openChat(userId, actualUserName);
    }
  }
  
  function showTemporaryMessage(message: string) {
    // Create a temporary notification for the sender
    const notification = document.createElement('div');
    notification.className = 'chat-status-message';
    notification.textContent = message;
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: linear-gradient(135deg, #4caf50, #45a049);
      color: white;
      padding: 1rem 1.5rem;
      border-radius: 10px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.3);
      z-index: 3000;
      animation: slideInDown 0.3s ease-out;
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
      notification.style.animation = 'slideOutUp 0.3s ease-in';
      setTimeout(() => {
        document.body.removeChild(notification);
      }, 300);
    }, 3000);
  }
  
  async function exitChat() {
    // Clean up presence
    await removePresence();
    
    // Clear online users list immediately
    onlineUsers = [];
    
    // Clean up subscriptions
    cleanupSubscriptions();
    
    // Navigate away
    currentView.set('home');
  }
  
  function handleVoiceTranscription(event: CustomEvent) {
    const { text } = event.detail;
    newMessage = newMessage ? `${newMessage} ${text}` : text;
  }
  
  function handleVoiceError(event: CustomEvent) {
    console.error('Voice recording error:', event.detail.message);
    alert(event.detail.message);
  }
  
  async function toggleFellowship(userId: string, userName: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Note: We can't save other users' profiles due to RLS policies
    // Their profile should already exist from when they signed up
    // We'll just use the userName passed in for display
    
    if (fellowships.has(userId)) {
      // Already in fellowship - DON'T remove from here, just show status
      console.log('Already in fellowship with', userName);
      // Could show a tooltip or message
      return; // Exit early - no removal from chat
    } else if (pendingRequests.has(userId)) {
      // Cancel pending request
      const { data, error } = await supabase
        .rpc('cancel_fellowship_request', {
          p_from_user_id: user.id,
          p_to_user_id: userId
        });
      
      if (!error) {
        pendingRequests.delete(userId);
        pendingRequests = new Set(pendingRequests);
      }
    } else if (incomingRequests.has(userId)) {
      // Accept incoming request
      const { data: requests } = await supabase
        .rpc('get_fellowship_requests', { p_user_id: user.id });
      
      const request = requests?.find((r: any) => 
        r.from_user_id === userId && r.direction === 'received'
      );
      
      if (request) {
        const { data, error } = await supabase
          .rpc('accept_fellowship_request', {
            p_request_id: request.request_id,
            p_user_id: user.id
          });
        
        if (error) {
          console.error('Error accepting request:', error);
          // Fallback: manually accept
          const { error: updateError } = await supabase
            .from('fellowship_requests')
            .update({ 
              status: 'accepted',
              responded_at: new Date().toISOString()
            })
            .eq('id', request.request_id)
            .eq('to_user_id', user.id);
          
          if (!updateError) {
            // Create our side of fellowship
            await supabase
              .from('fellowships')
              .insert({ user_id: user.id, fellow_id: userId });
          }
        }
        
        // Update UI state
        incomingRequests.delete(userId);
        incomingRequests = new Set(incomingRequests);
        fellowships.add(userId);
        fellowships = new Set(fellowships);
        requestCount = Math.max(0, requestCount - 1);
        
        // Reload to ensure consistency
        await loadFellowships();
        await loadFellowshipRequests();
      }
    } else {
      // Send new request
      const { data, error } = await supabase
        .rpc('send_fellowship_request', {
          p_from_user_id: user.id,
          p_to_user_id: userId
        });
      
      console.log('Send fellowship request result:', data, error);
      
      if (!error && data?.success) {
        if (data.message === 'Fellowship established (mutual request)') {
          // Mutual request - they're now fellows
          fellowships.add(userId);
          fellowships = new Set(fellowships);
          incomingRequests.delete(userId);
          incomingRequests = new Set(incomingRequests);
          requestCount = Math.max(0, requestCount - 1);
        } else {
          // Request sent
          pendingRequests.add(userId);
          pendingRequests = new Set(pendingRequests);
        }
      } else if (error) {
        console.error('Fellowship request error:', error);
        // Fallback: try direct fellowship add if requests system fails
        const { error: fellowshipError } = await supabase
          .from('fellowships')
          .insert({
            user_id: user.id,
            fellow_id: userId
          });
        
        if (!fellowshipError) {
          fellowships.add(userId);
          fellowships = new Set(fellowships);
          console.log('Added fellowship directly (fallback)');
        }
      }
    }
  }
</script>

<div class="sanctuary-container">
  <!-- Sidebar - Sacred Style -->
  <div class="sidebar">
    <div class="sidebar-header">
      <div class="sanctuary-emblem">⛪</div>
      <div class="sanctuary-title">THE WAY</div>
      <div class="sanctuary-subtitle">Where souls gather in His light</div>
      <button 
        class="fellowship-btn {requestCount > 0 ? 'has-requests' : ''}" 
        on:click={() => showFellowshipManager = true} 
        title="Manage Fellowship | Requests: {requestCount} | Incoming: {incomingRequests.size}"
      >
        👥 Fellowship
        {#if requestCount > 0}
          <span class="request-badge">{requestCount}</span>
        {/if}
      </button>
      <!-- Debug info -->
      {#if showDebug}
        <div style="position: absolute; top: 40px; right: 70px; background: black; color: white; padding: 5px; font-size: 10px; z-index: 9999;">
          Count: {requestCount}<br>
          Incoming: {incomingRequests.size}<br>
          Pending: {pendingRequests.size}<br>
          Fellows: {fellowships.size}<br>
          <button 
            style="margin-top: 5px; font-size: 10px; padding: 2px 5px;"
            on:click={async () => {
              await loadFellowshipRequests();
              await loadFellowships();
              console.log('Manually refreshed - Count:', requestCount);
            }}
          >
            🔄 Refresh
          </button>
        </div>
      {/if}
      <button class="exit-sanctuary" on:click={exitChat} title="Return to main app">
        ← Exit
      </button>
    </div>
    
    <div class="congregation">
      <div class="section-divider">In {currentRoom.name} • {onlineUsers.length} {onlineUsers.length === 1 ? 'soul' : 'souls'}</div>
      
      {#each onlineUsers as user}
        <div class="soul-vessel">
          <div class="soul-avatar">
            {getInitials(user.user_name || 'Anonymous')}
            <div class="presence-aura aura-{user.status || 'online'}"></div>
            {#if fellowships.has(user.user_id)}
              <span class="sidebar-fellowship-indicator" title="In your fellowship">👤</span>
            {/if}
            {#if usersInCounsel.has(user.user_id)}
              <span class="in-counsel-indicator" title="In private counsel">🤝</span>
            {/if}
          </div>
          <div class="soul-details">
            <div class="soul-name">{user.user_name || 'Anonymous Soul'}</div>
            <div class="soul-message">
              {statusConfig[user.status || 'online'].icon} {statusConfig[user.status || 'online'].label}
            </div>
          </div>
          {#if user.user_id !== $authStore?.id}
            <div class="soul-actions">
              {#if fellowships.has(user.user_id)}
                <button 
                  class="sidebar-dm-btn"
                  on:click|stopPropagation={() => openPrivateMessage(user.user_id, user.user_name || 'Anonymous')}
                  title="Send private message"
                >
                  💬
                </button>
              {/if}
              <button 
              class="sidebar-fellowship-btn {fellowships.has(user.user_id) ? 'active locked' : ''} {pendingRequests.has(user.user_id) ? 'pending' : ''} {incomingRequests.has(user.user_id) ? 'incoming' : ''}"
              on:click={() => toggleFellowship(user.user_id, user.user_name)}
              title={fellowships.has(user.user_id) ? '✓ In fellowship (manage in Fellowship Manager)' : 
                     pendingRequests.has(user.user_id) ? 'Cancel request' :
                     incomingRequests.has(user.user_id) ? 'Accept request' : 
                     'Send fellowship request'}
            >
              {#if fellowships.has(user.user_id)}
                <span>✓</span>
              {:else if pendingRequests.has(user.user_id)}
                <span>⏳</span>
              {:else if incomingRequests.has(user.user_id)}
                <span>✉️</span>
              {:else}
                <span>+</span>
              {/if}
            </button>
            </div>
          {/if}
        </div>
      {/each}
      
      {#if onlineUsers.length === 0}
        <div class="empty-congregation">
          Awaiting fellowship...
        </div>
      {/if}
    </div>
    
    <div class="sacred-scrolls">
      <div class="section-divider">
        {currentRoom.id === 'debate' ? 'Rules of Engagement' : 'Sacred Covenant'}
      </div>
      {#if currentRoom.id === 'debate'}
        <div class="scroll-item">⚖️ Seek understanding, not victory</div>
        <div class="scroll-item">📜 Ground arguments in Scripture</div>
        <div class="scroll-item">🤝 Respect opposing viewpoints</div>
        <div class="scroll-item">✨ Truth with grace & humility</div>
      {:else}
        <div class="scroll-item">Love one another as He loved us</div>
        <div class="scroll-item">Bear each other's burdens</div>
        <div class="scroll-item">Encourage with psalms & hymns</div>
        <div class="scroll-item">Speak truth wrapped in grace</div>
      {/if}
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
  
  <!-- Mobile Sidebar Overlay -->
  {#if showMobileSidebar}
    <div class="mobile-sidebar-overlay" on:click={() => showMobileSidebar = false}>
      <div class="mobile-sidebar" on:click|stopPropagation>
        <div class="mobile-sidebar-header">
          <div class="sanctuary-title">👥 Who's Here</div>
          <button class="close-mobile-sidebar" on:click={() => showMobileSidebar = false}>✕</button>
        </div>
        
        <!-- Users List for Mobile -->
        <div class="mobile-users-list">
          <div class="souls-present">
            <div class="souls-count">Souls Present: {onlineUsers.length}</div>
          </div>
          
          {#each onlineUsers as user}
            <div class="soul-entry">
              <div class="soul-essence">
                <div class="soul-name">{user.user_name || 'Anonymous'}</div>
                <div class="soul-message">
                  {statusConfig[user.status || 'online'].icon} {statusConfig[user.status || 'online'].label}
                </div>
              </div>
              {#if user.user_id !== $authStore?.id}
                <div class="soul-actions">
                  {#if fellowships.has(user.user_id)}
                    <button 
                      class="sidebar-dm-btn"
                      on:click|stopPropagation={() => {
                        openPrivateMessage(user.user_id, user.user_name || 'Anonymous');
                        showMobileSidebar = false;
                      }}
                      title="Send private message"
                    >
                      💬
                    </button>
                  {/if}
                  <button 
                    class="sidebar-fellowship-btn {fellowships.has(user.user_id) ? 'active locked' : ''} {pendingRequests.has(user.user_id) ? 'pending' : ''} {incomingRequests.has(user.user_id) ? 'incoming' : ''}"
                    on:click={() => {
                      toggleFellowship(user.user_id, user.user_name);
                      showMobileSidebar = false;
                    }}
                    title={fellowships.has(user.user_id) ? '✓ In fellowship (manage in Fellowship Manager)' : 
                           pendingRequests.has(user.user_id) ? 'Cancel request' :
                           incomingRequests.has(user.user_id) ? 'Accept/Decline fellowship' : 'Add to fellowship'}
                  >
                    {#if fellowships.has(user.user_id)}
                      ✓
                    {:else if pendingRequests.has(user.user_id)}
                      ⏳
                    {:else if incomingRequests.has(user.user_id)}
                      👋
                    {:else}
                      🤝
                    {/if}
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        </div>
        
        <!-- Fellowship Manager Button -->
        <div class="mobile-fellowship-section">
          <button 
            class="mobile-fellowship-btn {requestCount > 0 ? 'has-requests' : ''}" 
            on:click={() => {
              showFellowshipManager = true;
              showMobileSidebar = false;
            }}
            title="Manage Fellowship | Requests: {requestCount} | Incoming: {incomingRequests.size}"
          >
            👥 Fellowship Manager
            {#if requestCount > 0}
              <span class="request-badge">{requestCount}</span>
            {/if}
          </button>
        </div>
      </div>
    </div>
  {/if}
  
  <!-- Main Sanctuary -->
  <div class="sanctuary-hall">
    <div class="sanctuary-ceiling">
      <div class="hall-inscription">
        <div class="hall-name">✨ {currentRoom.name} ✨</div>
        <div class="divine-verse">"Behold, how good and pleasant it is when brothers dwell in unity!" - Psalm 133:1</div>
      </div>
      <!-- Mobile buttons -->
      <div class="mobile-buttons">
        <button class="mobile-users-btn" on:click={() => showMobileSidebar = true} title="View users">
          👥 ({onlineUsers.length})
        </button>
        <button class="mobile-exit-btn" on:click={exitChat} title="Exit chat">
          ← Exit
        </button>
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
              {#if fellowships.has(message.user_id)}
                <span class="fellowship-indicator" title="In your fellowship">👤</span>
              {/if}
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
                  <div class="prayer-dove">🕊️</div>
                {/if}
                {message.message}
              </div>
              {#if message.user_id !== $authStore?.id}
                <div class="message-flags">
                  <button 
                    class="flag-btn debate-room" 
                    class:active={message.message_flags?.some(f => f.flag_type === 'debate_room' && f.user_id === $authStore?.id)}
                    on:click={() => flagMessage(message.id, 'debate_room')}
                    title="Suggest moving to Debate Room"
                  >
                    <span>⚖️</span>
                    <span class="flag-text">Debate Room</span>
                    {#if message.message_flags?.filter(f => f.flag_type === 'debate_room').length > 0}
                      <span class="flag-count">({message.message_flags.filter(f => f.flag_type === 'debate_room').length})</span>
                    {/if}
                  </button>
                  <div class="flag-separator">|</div>
                  <button 
                    class="flag-btn not-the-way"
                    class:active={message.message_flags?.some(f => f.flag_type === 'not_the_way' && f.user_id === $authStore?.id)}
                    on:click={() => flagMessage(message.id, 'not_the_way')}
                    title="Flag as inappropriate"
                  >
                    <span>🚫</span>
                    <span class="flag-text">Not The Way</span>
                    {#if message.message_flags?.filter(f => f.flag_type === 'not_the_way').length > 0}
                      <span class="flag-count">({message.message_flags.filter(f => f.flag_type === 'not_the_way').length})</span>
                    {/if}
                  </button>
                </div>
              {/if}
              {#if message.hidden && message.user_id === $authStore?.id}
                <div class="hidden-notice">
                  ⚠️ This message has been hidden due to multiple flags
                </div>
              {/if}
              <div class="blessings-received">
                <button 
                  class="blessing" 
                  class:active={message.chat_reactions?.some(r => r.reaction === 'amen' && r.user_id === $authStore?.id)}
                  on:click={() => addReaction(message.id, 'amen')}
                >
                  <span>🙏</span>
                  <span class="blessing-count">
                    Amen {#if message.chat_reactions?.filter(r => r.reaction === 'amen').length > 0}
                      ({message.chat_reactions.filter(r => r.reaction === 'amen').length})
                    {/if}
                  </span>
                </button>
                <button 
                  class="blessing"
                  class:active={message.chat_reactions?.some(r => r.reaction === 'pray' && r.user_id === $authStore?.id)}
                  on:click={() => addReaction(message.id, 'pray')}
                >
                  <span>🤲</span>
                  <span class="blessing-count">
                    Praying {#if message.chat_reactions?.filter(r => r.reaction === 'pray').length > 0}
                      ({message.chat_reactions.filter(r => r.reaction === 'pray').length})
                    {/if}
                  </span>
                </button>
                <button 
                  class="blessing"
                  class:active={message.chat_reactions?.some(r => r.reaction === 'love' && r.user_id === $authStore?.id)}
                  on:click={() => addReaction(message.id, 'love')}
                >
                  <span>❤️</span>
                  <span class="blessing-count">
                    Love {#if message.chat_reactions?.filter(r => r.reaction === 'love').length > 0}
                      ({message.chat_reactions.filter(r => r.reaction === 'love').length})
                    {/if}
                  </span>
                </button>
                <button 
                  class="blessing"
                  class:active={message.chat_reactions?.some(r => r.reaction === 'hallelujah' && r.user_id === $authStore?.id)}
                  on:click={() => addReaction(message.id, 'hallelujah')}
                >
                  <span>🎉</span>
                  <span class="blessing-count">
                    Hallelujah {#if message.chat_reactions?.filter(r => r.reaction === 'hallelujah').length > 0}
                      ({message.chat_reactions.filter(r => r.reaction === 'hallelujah').length})
                    {/if}
                  </span>
                </button>
              </div>
            </div>
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="prayer-altar">
      <div class="altar-vessel" class:mobile={isMobile}>
        <textarea 
          class="prayer-inscription" 
          bind:value={newMessage}
          on:keydown={handleKeydown}
          on:input={() => console.log('Input changed:', newMessage)}
          placeholder={isMobile ? "Type message..." : "Inscribe your prayer, testimony, or word of encouragement..."}
          rows={isMobile ? "1" : "2"}
          enterkeyhint="send"
        ></textarea>
        <div class="altar-tools">
          {#if !isMobile}
            <VoiceRecorder
              placeholder="Speak your message..."
              on:transcription={handleVoiceTranscription}
              on:error={handleVoiceError}
            />
            <button class="altar-tool" title="Add Scripture (Coming Soon)" disabled>📜</button>
          {/if}
          <button class="altar-tool send-prayer" on:click={sendMessage} aria-label="Send message">
            {#if isMobile}
              <span class="send-icon-only">↑</span>
            {:else}
              <span class="send-text">Lift Up</span>
              <span class="send-icon">✨</span>
            {/if}
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<FellowshipManager bind:show={showFellowshipManager} />

<!-- Pop-out chat windows manager -->
<ChatPopoutManager 
  bind:this={chatPopoutManager}
  onCounselStatusChange={handleCounselStatusChange}
/>

{#if showDebug}
  <FellowshipDebug />
{/if}

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
  
  .fellowship-btn {
    position: absolute;
    top: 10px;
    right: 70px;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    border: 1px solid var(--border-gold);
    color: var(--bg-dark);
    padding: 6px 12px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .fellowship-btn:hover {
    transform: scale(1.05);
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.4);
  }
  
  .fellowship-btn.has-requests {
    animation: pulse 2s infinite;
    background: linear-gradient(135deg, #ff6b6b, #ff8787);
    border-color: #ff6b6b;
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
  
  .request-badge {
    position: absolute;
    top: -8px;
    right: -8px;
    background: #ff4444;
    color: white;
    border-radius: 50%;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: bold;
    border: 2px solid var(--bg-dark);
    animation: bounce 1s infinite;
  }
  
  @keyframes bounce {
    0%, 100% {
      transform: scale(1);
    }
    50% {
      transform: scale(1.1);
    }
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
  
  .sidebar-fellowship-indicator {
    position: absolute;
    bottom: -2px;
    right: -2px;
    font-size: 0.7rem;
    background: var(--bg-dark);
    border-radius: 50%;
    padding: 1px;
    border: 1px solid var(--border-gold);
  }
  
  .in-counsel-indicator {
    position: absolute;
    top: -2px;
    left: -2px;
    font-size: 0.75rem;
    background: linear-gradient(135deg, #9c27b0, #e91e63);
    border-radius: 50%;
    padding: 2px;
    border: 1px solid var(--bg-dark);
    animation: gentle-pulse 3s infinite;
    box-shadow: 0 0 10px rgba(233, 30, 99, 0.5);
  }
  
  @keyframes gentle-pulse {
    0%, 100% {
      transform: scale(1);
      opacity: 1;
    }
    50% {
      transform: scale(1.05);
      opacity: 0.9;
    }
  }
  
  .soul-actions {
    display: flex;
    gap: 0.5rem;
    margin-left: auto;
  }
  
  .sidebar-dm-btn {
    background: rgba(138, 43, 226, 0.15);
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 50%;
    width: 28px;
    height: 28px;
    cursor: pointer;
    font-size: 14px;
    transition: all 0.2s;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  
  .sidebar-dm-btn:hover {
    background: rgba(138, 43, 226, 0.3);
    transform: scale(1.1);
    box-shadow: 0 0 10px rgba(138, 43, 226, 0.4);
  }
  
  .sidebar-fellowship-btn {
    background: rgba(255, 215, 0, 0.15);
    border: 1px solid var(--border-gold);
    border-radius: 50%;
    width: 28px;
    height: 28px;
    cursor: pointer;
    font-size: 14px;
    transition: all 0.2s;
    color: var(--text-divine);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
  }
  
  .sidebar-fellowship-btn:hover {
    background: rgba(255, 215, 0, 0.3);
    transform: scale(1.1);
    box-shadow: 0 0 10px rgba(255, 215, 0, 0.4);
  }
  
  .sidebar-fellowship-btn.pending {
    background: rgba(255, 165, 0, 0.2);
    border-color: orange;
  }
  
  .sidebar-fellowship-btn.incoming {
    background: rgba(76, 175, 80, 0.2);
    border-color: #4caf50;
    animation: pulse 2s infinite;
  }
  
  .sidebar-fellowship-btn.active {
    background: rgba(76, 175, 80, 0.3);
    border-color: #4caf50;
    color: #4caf50;
  }
  
  .sidebar-fellowship-btn.locked {
    cursor: not-allowed;
    opacity: 0.8;
  }
  
  .sidebar-fellowship-btn.locked:hover {
    transform: none;
    background: rgba(76, 175, 80, 0.3);
  }
  
  @keyframes pulse {
    0%, 100% {
      transform: scale(1);
      box-shadow: 0 0 0 0 rgba(76, 175, 80, 0.4);
    }
    50% {
      transform: scale(1.05);
      box-shadow: 0 0 10px 5px rgba(76, 175, 80, 0.4);
    }
  }
  
  .sidebar-fellowship-btn span {
    line-height: 1;
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
  
  /* Mobile buttons - hidden by default, shown only on mobile */
  .mobile-buttons {
    display: none;
  }
  
  .mobile-users-btn {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 215, 0, 0.1));
    border: 1px solid var(--border-gold);
    color: var(--text-divine);
    padding: 8px 12px;
    border-radius: 8px;
    font-size: 0.9rem;
    cursor: pointer;
    transition: all 0.2s ease;
    backdrop-filter: blur(10px);
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
  
  .mobile-exit-btn {
    display: none;
    background: rgba(255, 67, 54, 0.2);
    border: 1px solid rgba(255, 67, 54, 0.4);
    color: #ff6b6b;
    padding: 6px 12px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .mobile-exit-btn:hover {
    background: rgba(255, 67, 54, 0.3);
    transform: scale(1.05);
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
  
  .fellowship-indicator {
    position: absolute;
    bottom: -2px;
    right: -2px;
    font-size: 0.75rem;
    background: var(--bg-dark);
    border-radius: 50%;
    padding: 2px;
    border: 1px solid var(--border-gold);
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
    position: relative;
    z-index: 1;
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
  
  .prayer-dove {
    position: absolute;
    right: 15px;
    top: 50%;
    transform: translateY(-50%);
    font-size: 50px;
    opacity: 0.1;
    pointer-events: none;
    animation: float-dove 6s ease-in-out infinite;
    z-index: 0;
  }
  
  @keyframes float-dove {
    0%, 100% { 
      transform: translateY(-50%) translateX(0) rotate(-10deg); 
      opacity: 0.1;
    }
    50% { 
      transform: translateY(-55%) translateX(-3px) rotate(5deg);
      opacity: 0.15;
    }
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
  
  .blessing.active {
    background: radial-gradient(circle, rgba(255, 215, 0, 0.4), rgba(138, 43, 226, 0.2));
    border-color: var(--primary-gold);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.4);
    transform: scale(1.05);
  }
  
  .blessing.active:hover {
    transform: scale(1.1);
  }
  
  .blessing-count {
    font-size: 11px;
    font-weight: 600;
  }
  
  /* Message Flags */
  .message-flags {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
    justify-content: flex-end;
    padding-top: 8px;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .flag-separator {
    color: rgba(255, 255, 255, 0.2);
    font-size: 0.8rem;
    padding: 0 4px;
  }
  
  .flag-btn {
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.1);
    padding: 4px 10px;
    border-radius: 16px;
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    transition: all 0.3s;
    color: rgba(255, 255, 255, 0.5);
    font-size: 0.85rem;
    opacity: 0.6;
  }
  
  .flag-btn:hover {
    opacity: 1;
  }
  
  .flag-btn.debate-room {
    border-color: rgba(255, 193, 7, 0.3);
  }
  
  .flag-btn.debate-room:hover {
    background: rgba(255, 193, 7, 0.1);
    border-color: rgba(255, 193, 7, 0.5);
    color: #ffc107;
  }
  
  .flag-btn.debate-room.active {
    background: rgba(255, 193, 7, 0.2);
    border-color: #ffc107;
    color: #ffc107;
    opacity: 1;
  }
  
  .flag-btn.not-the-way {
    border-color: rgba(244, 67, 54, 0.3);
  }
  
  .flag-btn.not-the-way:hover {
    background: rgba(244, 67, 54, 0.1);
    border-color: rgba(244, 67, 54, 0.5);
    color: #f44336;
  }
  
  .flag-btn.not-the-way.active {
    background: rgba(244, 67, 54, 0.2);
    border-color: #f44336;
    color: #f44336;
    opacity: 1;
  }
  
  .flag-text {
    font-size: 0.8rem;
  }
  
  .flag-count {
    font-size: 0.75rem;
    opacity: 0.8;
  }
  
  .hidden-notice {
    background: rgba(244, 67, 54, 0.1);
    border: 1px solid rgba(244, 67, 54, 0.3);
    color: #f44336;
    padding: 8px 12px;
    border-radius: 8px;
    margin-top: 8px;
    font-size: 0.9rem;
    text-align: center;
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
  
  .altar-tool:hover:not(:disabled) {
    color: var(--text-divine);
    transform: scale(1.2);
    filter: drop-shadow(0 0 10px currentColor);
  }
  
  .altar-tool:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  .altar-tool:disabled:hover::after {
    content: "Coming Soon!";
    position: absolute;
    bottom: 100%;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0, 0, 0, 0.8);
    color: var(--text-divine);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    white-space: nowrap;
    pointer-events: none;
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
  
  .send-icon-only {
    font-size: 20px;
    font-weight: bold;
    transform: rotate(90deg);
  }
  
  /* Mobile-specific altar layout */
  .altar-vessel.mobile {
    flex-direction: row;
    align-items: flex-end;
    padding: 8px;
    gap: 8px;
  }
  
  .altar-vessel.mobile .prayer-inscription {
    min-height: 36px;
    max-height: 100px;
    padding: 8px 12px;
    font-size: 16px; /* Prevent zoom on iOS */
  }
  
  .altar-vessel.mobile .altar-tools {
    flex-shrink: 0;
    gap: 4px;
  }
  
  .altar-vessel.mobile .send-prayer {
    width: 36px;
    height: 36px;
    padding: 0;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #007AFF, #0051D5);
  }
  
  .altar-vessel.mobile .send-prayer:active {
    transform: scale(0.95);
  }
  
  @media (max-width: 768px) {
    .sanctuary-container {
      flex-direction: column;
      height: 100vh;
      height: 100dvh;
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      overflow: hidden;
    }
    
    .sidebar {
      display: none;
    }
    
    .mobile-exit-btn {
      display: inline-block;
      position: static;
    }
    
    .mobile-buttons {
      display: flex;
    }
    
    .mobile-users-btn {
      display: inline-block;
    }
    
    .sanctuary-ceiling {
      position: relative;
      padding: 20px 140px 20px 20px; /* Right padding for mobile buttons */
      flex-shrink: 0; /* Prevent header from shrinking */
      height: auto;
    }
    
    .mobile-buttons {
      position: absolute;
      top: 50%;
      right: 10px;
      transform: translateY(-50%);
      display: flex;
      flex-direction: row;
      gap: 8px;
      align-items: center;
    }
    
    .mobile-users-btn {
      background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 215, 0, 0.1));
      border: 1px solid var(--border-gold);
      color: var(--text-divine);
      padding: 8px 12px;
      border-radius: 8px;
      font-size: 0.9rem;
      cursor: pointer;
      transition: all 0.2s ease;
      backdrop-filter: blur(10px);
    }
    
    .mobile-users-btn:hover {
      background: linear-gradient(135deg, rgba(255, 215, 0, 0.3), rgba(255, 215, 0, 0.2));
      transform: translateY(-1px);
    }
    
    .mobile-sidebar-overlay {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0, 0, 0, 0.8);
      backdrop-filter: blur(5px);
      z-index: 3000;
      display: flex;
      align-items: flex-start;
      justify-content: flex-end;
      padding: 0;
    }
    
    .mobile-sidebar {
      background: linear-gradient(135deg, #1a1a2e, #0f0f1e);
      border-left: 2px solid var(--border-gold);
      border-radius: 15px 0 0 15px;
      width: 80%;
      max-width: 350px;
      height: 100%;
      display: flex;
      flex-direction: column;
      box-shadow: -20px 0 60px rgba(0, 0, 0, 0.8),
                  0 0 40px rgba(255, 215, 0, 0.2);
      overflow: hidden;
    }
    
    .mobile-sidebar-header {
      padding: 1rem 1.5rem;
      border-bottom: 1px solid var(--border-gold);
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(138, 43, 226, 0.05));
      flex-shrink: 0;
    }
    
    .close-mobile-sidebar {
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
    
    .close-mobile-sidebar:hover {
      color: var(--text-divine);
      transform: scale(1.1);
    }
    
    .mobile-users-list {
      flex: 1;
      overflow-y: auto;
      padding: 1rem;
    }
    
    .mobile-fellowship-section {
      padding: 1rem;
      border-top: 1px solid var(--border-gold);
      background: rgba(0, 0, 0, 0.3);
      flex-shrink: 0;
    }
    
    .mobile-fellowship-btn {
      width: 100%;
      padding: 0.75rem 1rem;
      background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(138, 43, 226, 0.1));
      border: 1px solid rgba(138, 43, 226, 0.3);
      color: var(--text-light);
      border-radius: 8px;
      font-size: 1rem;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
    }
    
    .mobile-fellowship-btn:hover {
      background: linear-gradient(135deg, rgba(138, 43, 226, 0.3), rgba(138, 43, 226, 0.2));
      transform: translateY(-2px);
    }
    
    .mobile-fellowship-btn.has-requests {
      background: linear-gradient(135deg, rgba(255, 193, 7, 0.2), rgba(255, 193, 7, 0.1));
      border-color: rgba(255, 193, 7, 0.3);
      animation: pulse 2s infinite;
    }
    
    .chamber-selection {
      padding: 0 10px;
      gap: 1px;
      flex-shrink: 0;
      overflow-x: auto;
      -webkit-overflow-scrolling: touch;
    }
    
    .chamber-portal {
      padding: 8px 12px;
      font-size: 12px;
    }
    
    /* Mobile chat input improvements */
    .prayer-altar {
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      padding: 8px;
      background: rgba(0, 0, 0, 0.95);
      border-top: 1px solid var(--border-gold);
      z-index: 100;
    }
    
    .sanctuary-hall {
      display: flex;
      flex-direction: column;
      height: 100%;
      width: 100%;
      overflow: hidden;
    }
    
    .sacred-chamber {
      flex: 1;
      overflow-y: scroll;
      -webkit-overflow-scrolling: touch; /* Smooth scrolling on iOS */
      padding: 10px;
      padding-bottom: 100px; /* Space for fixed input */
      min-height: 0; /* Important for flex children */
    }
    
    .divine-message {
      margin: 8px;
    }
    
    .message-flags {
      flex-wrap: nowrap;
      gap: 4px;
    }
    
    .flag-btn {
      padding: 3px 8px;
      font-size: 0.75rem;
    }
    
    .flag-text {
      font-size: 0.7rem;
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
    .mobile-exit-btn {
      padding: 5px 10px;
      font-size: 11px;
    }
    
    .hall-name {
      font-size: 16px;
    }
    
    .divine-verse {
      display: none;
    }
    
    .sanctuary-ceiling {
      padding: 12px;
      padding-right: 70px;
    }
    
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
  
  /* CSS animations for temporary notifications */
  :global(.chat-status-message) {
    animation: slideInDown 0.3s ease-out;
  }
  
  @keyframes slideInDown {
    from {
      transform: translate(-50%, -100%);
      opacity: 0;
    }
    to {
      transform: translate(-50%, 0);
      opacity: 1;
    }
  }
  
  @keyframes slideOutUp {
    from {
      transform: translate(-50%, 0);
      opacity: 1;
    }
    to {
      transform: translate(-50%, -100%);
      opacity: 0;
    }
  }
</style>