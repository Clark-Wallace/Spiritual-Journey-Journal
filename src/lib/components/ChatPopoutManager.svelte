<script lang="ts">
  import { onMount } from 'svelte';
  import ChatPopout from './ChatPopout.svelte';
  import ChatRequestNotification from './ChatRequestNotification.svelte';
  
  export let onCounselStatusChange: ((usersInCounsel: string[]) => void) | null = null;
  
  interface ChatWindow {
    id: string;
    recipientId: string;
    recipientName: string;
    position: { x: number; y: number };
    zIndex: number;
  }
  
  let chatWindows: ChatWindow[] = [];
  let nextZIndex = 1000;
  let nextPosition = { x: 100, y: 100 };
  
  // Update counsel status when windows change
  $: if (onCounselStatusChange) {
    const activeUserIds = chatWindows.map(w => w.recipientId);
    onCounselStatusChange(activeUserIds);
  }
  
  export function openChat(recipientId: string, recipientName: string) {
    // Check if chat already exists
    const existing = chatWindows.find(w => w.recipientId === recipientId);
    if (existing) {
      // Bring to front
      bringToFront(existing.id);
      return;
    }
    
    // Determine position based on screen size
    const isMobile = window.innerWidth <= 768;
    const windowPosition = isMobile 
      ? { x: window.innerWidth / 2 - 175, y: window.innerHeight / 2 - 300 }
      : { ...nextPosition };
    
    // Create new window
    const newWindow: ChatWindow = {
      id: `chat-${Date.now()}`,
      recipientId,
      recipientName,
      position: windowPosition,
      zIndex: nextZIndex++
    };
    
    chatWindows = [...chatWindows, newWindow];
    
    // Cascade next window position
    nextPosition = {
      x: (nextPosition.x + 30) % (window.innerWidth - 400),
      y: (nextPosition.y + 30) % (window.innerHeight - 500)
    };
    
    // Ensure minimum position
    if (nextPosition.x < 50) nextPosition.x = 50;
    if (nextPosition.y < 50) nextPosition.y = 50;
  }
  
  function closeChat(windowId: string) {
    chatWindows = chatWindows.filter(w => w.id !== windowId);
  }
  
  function bringToFront(windowId: string) {
    const window = chatWindows.find(w => w.id === windowId);
    if (window) {
      window.zIndex = nextZIndex++;
      chatWindows = chatWindows;
    }
  }
  
  function handleAcceptChat(fromUserId: string, fromUserName: string) {
    openChat(fromUserId, fromUserName);
  }
  
  function handleChatRequestAccepted(userId: string, userName: string) {
    // When our chat request is accepted, open the chat window
    openChat(userId, userName);
  }
  
  // Note: openChat is exposed globally via App.svelte, not here
</script>

<!-- Chat request notifications -->
<ChatRequestNotification 
  onAcceptChat={handleAcceptChat}
  onChatRequestAccepted={handleChatRequestAccepted}
/>

<!-- Render all chat windows -->
{#each chatWindows as window (window.id)}
  <ChatPopout
    recipientId={window.recipientId}
    recipientName={window.recipientName}
    onClose={() => closeChat(window.id)}
    zIndex={window.zIndex}
    initialPosition={window.position}
  />
{/each}

<style>
  /* No styles needed - all handled by ChatPopout */
</style>