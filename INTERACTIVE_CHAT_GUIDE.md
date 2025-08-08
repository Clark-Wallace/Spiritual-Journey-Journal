# Interactive Real-Time Chat Implementation Guide

## Complete Solution for Building Seamless Chat Experiences

This guide documents the complete implementation of a production-ready, real-time chat system with multiple rooms, presence tracking, reactions, and zero-flicker updates. Built with Svelte, TypeScript, and Supabase.

## Table of Contents
1. [Database Schema](#database-schema)
2. [Real-Time Subscriptions](#real-time-subscriptions)
3. [Presence System](#presence-system)
4. [Message Reactions](#message-reactions)
5. [Mobile Optimization](#mobile-optimization)
6. [Zero-Flicker Implementation](#zero-flicker-implementation)
7. [Moderation System](#moderation-system)
8. [Common Issues & Solutions](#common-issues--solutions)

---

## Database Schema

### Core Tables Required

```sql
-- Chat Messages Table
CREATE TABLE chat_messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  user_name TEXT,
  message TEXT NOT NULL,
  room VARCHAR(50) DEFAULT 'general', -- CRITICAL: Add room column
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  hidden BOOLEAN DEFAULT false -- For moderation
);

-- User Presence Table (Per-Room)
CREATE TABLE user_presence (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  user_name TEXT,
  status VARCHAR(20) DEFAULT 'online',
  room VARCHAR(50) DEFAULT 'general', -- CRITICAL: Track per room
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, room) -- One presence per user per room
);

-- Chat Reactions Table
CREATE TABLE chat_reactions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  reaction VARCHAR(50) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id, reaction) -- Prevent duplicate reactions
);

-- Message Flags for Moderation
CREATE TABLE message_flags (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  flag_type TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id, flag_type)
);
```

### Enable Real-Time & RLS

```sql
-- Enable real-time for all tables
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE user_presence;
ALTER PUBLICATION supabase_realtime ADD TABLE chat_reactions;
ALTER PUBLICATION supabase_realtime ADD TABLE message_flags;

-- Enable RLS
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_flags ENABLE ROW LEVEL SECURITY;

-- Basic RLS Policies
CREATE POLICY "Users can view messages" ON chat_messages
  FOR SELECT USING (hidden = false OR user_id = auth.uid());

CREATE POLICY "Users can insert own messages" ON chat_messages
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can manage own reactions" ON chat_reactions
  FOR ALL USING (auth.uid() = user_id);
```

---

## Real-Time Subscriptions

### Setting Up Room-Based Subscriptions

```typescript
// CRITICAL: Clean up old subscriptions before creating new ones
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
        filter: `room=eq.${currentRoom.id}` // Filter by room
      },
      (payload) => {
        // Add new message to UI without reload
        messages = [payload.new, ...messages];
      }
    )
    .on('postgres_changes',
      { 
        event: '*', 
        schema: 'public', 
        table: 'chat_reactions'
      },
      (payload) => {
        // Update reactions WITHOUT reloading
        updateReactionInMessages(payload);
      }
    )
    .subscribe();
}

// CRITICAL: Clean up when switching rooms
async function switchRoom(newRoom: ChatRoom) {
  cleanupSubscriptions();
  await removePresence();
  currentRoom = newRoom;
  await loadMessages();
  await updatePresence();
  setupRealtimeSubscriptions();
}
```

---

## Presence System

### Per-Room Presence Tracking

```typescript
// Update presence for current room
async function updatePresence() {
  const user = await getCurrentUser();
  if (!user) return;
  
  const { error } = await supabase
    .from('user_presence')
    .upsert({
      user_id: user.id,
      user_name: userInfo?.name || user.email?.split('@')[0],
      status: currentStatus,
      room: currentRoom.id, // Track per room
      last_seen: new Date().toISOString()
    }, {
      onConflict: 'user_id,room' // Upsert based on user AND room
    });
}

// Remove presence when leaving
async function removePresence() {
  const user = await getCurrentUser();
  if (!user) return;
  
  await supabase
    .from('user_presence')
    .delete()
    .eq('user_id', user.id)
    .eq('room', currentRoom.id);
}

// Load presence for current room
async function loadPresence() {
  const { data } = await supabase
    .from('user_presence')
    .select('*')
    .eq('room', currentRoom.id)
    .gte('last_seen', new Date(Date.now() - 5 * 60 * 1000).toISOString());
  
  onlineUsers = data || [];
}
```

---

## Message Reactions

### Toggle-able Reactions Implementation

```typescript
async function addReaction(messageId: string, reaction: string) {
  const user = await getCurrentUser();
  if (!user) return;
  
  // Find the message
  const messageIndex = messages.findIndex(m => m.id === messageId);
  if (messageIndex === -1) return;
  
  // Check if user already has this reaction
  const existingReaction = messages[messageIndex].chat_reactions?.find(
    r => r.user_id === user.id && r.reaction === reaction
  );
  
  if (existingReaction) {
    // Remove reaction (toggle off)
    const { error } = await supabase
      .from('chat_reactions')
      .delete()
      .eq('message_id', messageId)
      .eq('user_id', user.id)
      .eq('reaction', reaction);
    
    // Update locally immediately
    messages[messageIndex].chat_reactions = 
      messages[messageIndex].chat_reactions.filter(
        r => !(r.user_id === user.id && r.reaction === reaction)
      );
  } else {
    // Add reaction (toggle on)
    await supabase
      .from('chat_reactions')
      .insert({
        message_id: messageId,
        user_id: user.id,
        reaction
      });
    
    // Update locally immediately
    if (!messages[messageIndex].chat_reactions) {
      messages[messageIndex].chat_reactions = [];
    }
    messages[messageIndex].chat_reactions.push({
      reaction,
      user_id: user.id
    });
  }
  
  // Trigger Svelte reactivity
  messages = messages;
}
```

---

## Mobile Optimization

### Full-Screen Mobile Chat Experience

```svelte
<style>
  /* Full height mobile chat */
  .chat-container {
    height: 100vh;
    display: flex;
    flex-direction: column;
    position: relative;
  }
  
  .messages-container {
    flex: 1;
    overflow-y: auto;
    min-height: 0; /* CRITICAL for flex children */
    -webkit-overflow-scrolling: touch; /* Smooth iOS scrolling */
  }
  
  /* Fixed input at bottom */
  .input-section {
    position: sticky;
    bottom: 0;
    background: var(--bg-dark);
    border-top: 1px solid var(--border-gold);
    padding: 0.75rem;
    z-index: 10;
  }
  
  /* iOS-style send button */
  .send-btn-mobile {
    position: absolute;
    right: 10px;
    bottom: 10px;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: #007AFF;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  
  /* Mobile-specific adjustments */
  @media (max-width: 768px) {
    .chat-container {
      height: calc(100vh - 60px); /* Account for nav bar */
    }
    
    .message-input {
      padding-right: 45px; /* Space for send button */
      font-size: 16px; /* Prevent iOS zoom */
    }
    
    /* Hide desktop-only features */
    .voice-recorder {
      display: none;
    }
  }
</style>
```

### iOS Keyboard Integration

```svelte
<!-- Support iOS "Done" button to send -->
<input
  type="text"
  class="message-input"
  placeholder="Type your message..."
  bind:value={newMessage}
  on:keydown={(e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      sendMessage();
    }
  }}
  enterkeyhint="send" <!-- iOS Done button becomes Send -->
/>
```

---

## Zero-Flicker Implementation

### The Problem
Real-time subscriptions calling `loadMessages()` or `loadPosts()` cause the entire UI to re-render, creating jarring flickers.

### The Solution: Granular Updates

```typescript
// NEVER do this in subscriptions:
.on('postgres_changes', { table: 'chat_reactions' }, () => {
  loadMessages(); // ❌ Causes full reload and flicker
})

// ALWAYS do this instead:
.on('postgres_changes', { table: 'chat_reactions' }, (payload) => {
  updateReactionInMessages(payload); // ✅ Updates only affected message
})

// Granular update function
function updateReactionInMessages(payload: any) {
  const { eventType, new: newData, old: oldData } = payload;
  const messageId = newData?.message_id || oldData?.message_id;
  
  if (!messageId) return;
  
  const messageIndex = messages.findIndex(m => m.id === messageId);
  if (messageIndex === -1) return;
  
  if (eventType === 'INSERT') {
    // Add reaction to specific message
    if (!messages[messageIndex].chat_reactions) {
      messages[messageIndex].chat_reactions = [];
    }
    messages[messageIndex].chat_reactions.push({
      reaction: newData.reaction,
      user_id: newData.user_id
    });
  } else if (eventType === 'DELETE') {
    // Remove reaction from specific message
    if (messages[messageIndex].chat_reactions) {
      messages[messageIndex].chat_reactions = 
        messages[messageIndex].chat_reactions.filter(
          r => !(r.reaction === oldData.reaction && 
                 r.user_id === oldData.user_id)
        );
    }
  }
  
  // Trigger Svelte reactivity
  messages = messages;
}
```

### Optimistic Updates Pattern

```typescript
async function sendMessage() {
  const user = await getCurrentUser();
  if (!user || !newMessage.trim()) return;
  
  // Create message object
  const tempMessage = {
    id: crypto.randomUUID(),
    user_id: user.id,
    user_name: userInfo?.name || 'User',
    message: newMessage,
    room: currentRoom.id,
    created_at: new Date().toISOString(),
    chat_reactions: []
  };
  
  // Add to UI immediately (optimistic update)
  messages = [tempMessage, ...messages];
  newMessage = '';
  
  // Then persist to database
  const { error } = await supabase
    .from('chat_messages')
    .insert({
      user_id: user.id,
      user_name: tempMessage.user_name,
      message: tempMessage.message,
      room: currentRoom.id
    });
  
  if (error) {
    // Revert on error
    messages = messages.filter(m => m.id !== tempMessage.id);
    newMessage = tempMessage.message;
    console.error('Failed to send message:', error);
  }
}
```

---

## Moderation System

### Community-Driven Flagging

```typescript
async function flagMessage(messageId: string, flagType: string) {
  const user = await getCurrentUser();
  if (!user) return;
  
  // Find message locally
  const messageIndex = messages.findIndex(m => m.id === messageId);
  if (messageIndex === -1) return;
  
  // Check if already flagged by this user
  const existingFlag = messages[messageIndex].message_flags?.find(
    f => f.flag_type === flagType && f.user_id === user.id
  );
  
  if (existingFlag) {
    // Remove flag (toggle off)
    await supabase
      .from('message_flags')
      .delete()
      .eq('message_id', messageId)
      .eq('user_id', user.id)
      .eq('flag_type', flagType);
    
    // Update locally
    messages[messageIndex].message_flags = 
      messages[messageIndex].message_flags.filter(
        f => f.id !== existingFlag.id
      );
  } else {
    // Add flag
    await supabase
      .from('message_flags')
      .insert({
        message_id: messageId,
        user_id: user.id,
        flag_type: flagType
      });
    
    // Update locally
    if (!messages[messageIndex].message_flags) {
      messages[messageIndex].message_flags = [];
    }
    messages[messageIndex].message_flags.push({
      flag_type: flagType,
      user_id: user.id
    });
  }
  
  // Check if message should be hidden (3+ flags)
  const flagCount = messages[messageIndex].message_flags
    ?.filter(f => f.flag_type === 'inappropriate').length || 0;
  
  if (flagCount >= 3) {
    messages[messageIndex].hidden = true;
  }
  
  messages = messages;
}
```

---

## Common Issues & Solutions

### Issue 1: Messages Not Sending
**Symptom:** Chat input clears but message doesn't appear
**Solution:** Ensure `room` column exists in chat_messages table
```sql
ALTER TABLE chat_messages 
ADD COLUMN IF NOT EXISTS room VARCHAR(50) DEFAULT 'general';
```

### Issue 2: Reactions Not Toggling
**Symptom:** Can add reactions but can't remove them
**Solution:** Fix RLS policy and ensure UNIQUE constraint
```sql
-- Add unique constraint
ALTER TABLE chat_reactions 
ADD CONSTRAINT unique_user_message_reaction 
UNIQUE(message_id, user_id, reaction);

-- Fix RLS policy
CREATE POLICY "Users can manage own reactions" ON chat_reactions
  FOR ALL USING (auth.uid() = user_id);
```

### Issue 3: Real-time Updates Not Working
**Symptom:** Other users' messages don't appear
**Solution:** Enable real-time and check subscription
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
```

### Issue 4: Mobile Scrolling Broken
**Symptom:** Can't scroll through messages on mobile
**Solution:** Fix flex container and overflow
```css
.messages-container {
  flex: 1;
  overflow-y: auto;
  min-height: 0; /* Critical! */
  -webkit-overflow-scrolling: touch;
}
```

### Issue 5: Presence Not Updating
**Symptom:** Users appear offline when they're online
**Solution:** Ensure room column and proper cleanup
```typescript
// Update presence every 30 seconds
const presenceInterval = setInterval(updatePresence, 30000);

// Clean up on component destroy
onDestroy(async () => {
  clearInterval(presenceInterval);
  await removePresence();
});
```

### Issue 6: Flickering on Interactions
**Symptom:** Screen flashes when clicking reactions
**Solution:** Never call full reload functions in subscriptions
```typescript
// Wrong way
.on('postgres_changes', table: 'reactions', () => {
  loadMessages(); // ❌ Full reload
})

// Right way
.on('postgres_changes', table: 'reactions', (payload) => {
  updateLocalState(payload); // ✅ Granular update
})
```

---

## Performance Tips

1. **Batch Database Operations**
   ```typescript
   // Load all related data in one query
   const { data } = await supabase
     .from('chat_messages')
     .select(`
       *,
       chat_reactions (*),
       message_flags (*)
     `)
     .eq('room', currentRoom.id)
     .order('created_at', { ascending: false })
     .limit(50);
   ```

2. **Implement Virtual Scrolling for Large Chats**
   ```typescript
   // Only render visible messages
   $: visibleMessages = messages.slice(0, 50);
   
   // Load more on scroll
   function handleScroll(e) {
     if (e.target.scrollTop > e.target.scrollHeight - 1000) {
       loadMoreMessages();
     }
   }
   ```

3. **Debounce Presence Updates**
   ```typescript
   import { debounce } from 'lodash';
   
   const debouncedPresenceUpdate = debounce(updatePresence, 5000);
   ```

4. **Use Connection Pooling**
   ```typescript
   // Reuse Supabase client instance
   export const supabase = createClient(url, key, {
     realtime: {
       params: {
         eventsPerSecond: 10
       }
     }
   });
   ```

---

## Testing Checklist

- [ ] Messages send and appear instantly
- [ ] Can switch between rooms without issues
- [ ] Reactions toggle on/off correctly
- [ ] Presence updates show correct users
- [ ] Mobile scrolling works smoothly
- [ ] No flickering on any interactions
- [ ] Flagged messages hide after threshold
- [ ] Real-time updates work across tabs
- [ ] iOS keyboard "Done" sends message
- [ ] Voice input works on desktop only

---

## Summary

This implementation provides:
- ⚡ **Zero-flicker real-time updates**
- 🔄 **Per-room presence tracking**
- 💬 **Toggle-able reactions**
- 📱 **Full mobile optimization**
- 🛡️ **Community moderation**
- 🚀 **Optimistic updates for instant feedback**

The key to success is **granular state updates** instead of full reloads, proper **subscription cleanup**, and **optimistic UI updates** with error handling.

---

*Last Updated: From production implementation of Spiritual Journey app*
*Tested with: Svelte 5, Supabase 2.x, TypeScript 5.x*