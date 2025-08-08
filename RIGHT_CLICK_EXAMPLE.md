# Right-Click Context Menu Examples for Svelte

## Using the ContextMenu Component

### Example 1: Community Feed Post Actions

```svelte
<script>
  import ContextMenu from './ContextMenu.svelte';
  
  let showContextMenu = false;
  let contextMenuX = 0;
  let contextMenuY = 0;
  let selectedPost = null;
  
  function handlePostRightClick(event, post) {
    event.preventDefault();
    
    selectedPost = post;
    contextMenuX = event.clientX;
    contextMenuY = event.clientY;
    showContextMenu = true;
  }
  
  $: contextMenuItems = selectedPost ? [
    {
      label: 'Copy Post',
      icon: '📋',
      action: () => {
        navigator.clipboard.writeText(selectedPost.content);
        alert('Post copied!');
      }
    },
    {
      label: 'Share Post',
      icon: '↗️',
      action: () => {
        // Share logic
      }
    },
    { divider: true },
    {
      label: 'Add to Prayer List',
      icon: '🙏',
      action: () => {
        // Add to prayer list
      }
    },
    {
      label: 'Save for Later',
      icon: '🔖',
      action: () => {
        // Save post
      }
    },
    { divider: true },
    {
      label: 'Report Post',
      icon: '🚩',
      action: () => {
        // Report logic
      }
    }
  ] : [];
</script>

<!-- In your post card -->
<div 
  class="post-card"
  on:contextmenu={(e) => handlePostRightClick(e, post)}
>
  <!-- Post content -->
</div>

<ContextMenu 
  bind:show={showContextMenu}
  x={contextMenuX}
  y={contextMenuY}
  items={contextMenuItems}
/>
```

### Example 2: Journal Entry Actions

```svelte
function handleJournalRightClick(event, entry) {
  event.preventDefault();
  
  const menuItems = [
    {
      label: 'Edit Entry',
      icon: '✏️',
      action: () => editEntry(entry)
    },
    {
      label: 'Share to Community',
      icon: '🌍',
      action: () => shareEntry(entry)
    },
    {
      label: 'Export as PDF',
      icon: '📄',
      action: () => exportPDF(entry)
    },
    { divider: true },
    {
      label: 'Delete Entry',
      icon: '🗑️',
      action: () => deleteEntry(entry)
    }
  ];
  
  showContextMenu(event.clientX, event.clientY, menuItems);
}
```

### Example 3: Chat Message Actions

```svelte
function handleMessageRightClick(event, message) {
  event.preventDefault();
  
  const isOwnMessage = message.user_id === currentUser.id;
  
  const menuItems = [
    {
      label: 'Reply',
      icon: '💬',
      action: () => replyToMessage(message)
    },
    {
      label: 'Copy Text',
      icon: '📋',
      action: () => navigator.clipboard.writeText(message.text)
    },
    ...(isOwnMessage ? [
      { divider: true },
      {
        label: 'Edit',
        icon: '✏️',
        action: () => editMessage(message)
      },
      {
        label: 'Delete',
        icon: '🗑️',
        action: () => deleteMessage(message)
      }
    ] : [
      { divider: true },
      {
        label: 'Report',
        icon: '🚩',
        action: () => reportMessage(message)
      }
    ])
  ];
  
  showContextMenu(event.clientX, event.clientY, menuItems);
}
```

## Native Browser Context Menu Customization

If you want to modify (not replace) the browser's context menu:

```svelte
<script>
  function handleContextMenu(e) {
    // You can't directly modify the browser menu,
    // but you can prevent it and show your own
    e.preventDefault();
    
    // Or conditionally allow it
    if (e.shiftKey) {
      // Shift+right-click shows browser menu
      return;
    }
    
    // Show custom menu
    showCustomMenu(e);
  }
</script>
```

## Keyboard Shortcuts with Right-Click

```svelte
<script>
  function handleRightClick(e) {
    e.preventDefault();
    
    if (e.ctrlKey) {
      // Ctrl + Right-click
      showAdvancedMenu();
    } else if (e.altKey) {
      // Alt + Right-click
      showDebugMenu();
    } else {
      // Normal right-click
      showNormalMenu();
    }
  }
</script>
```

## Touch Device Support (Long Press)

```svelte
<script>
  let pressTimer;
  
  function handleTouchStart(e, item) {
    pressTimer = setTimeout(() => {
      // Simulate right-click after 500ms press
      const touch = e.touches[0];
      handleRightClick({
        preventDefault: () => {},
        clientX: touch.clientX,
        clientY: touch.clientY
      }, item);
    }, 500);
  }
  
  function handleTouchEnd() {
    clearTimeout(pressTimer);
  }
</script>

<div
  on:touchstart={(e) => handleTouchStart(e, post)}
  on:touchend={handleTouchEnd}
  on:contextmenu={(e) => handleRightClick(e, post)}
>
  <!-- Content -->
</div>
```

## Implementation Ideas for Your App

### 1. **Community Feed**
- Copy post text
- Share to external platforms
- Save post for later
- Add to prayer list
- Report inappropriate content

### 2. **Journal Entries**
- Edit entry
- Share to community
- Export as PDF/image
- Add to favorites
- Delete entry

### 3. **Chat Messages**
- Reply to message
- Copy message
- Edit (own messages)
- Delete (own messages)
- Report (others' messages)
- Add reaction

### 4. **Scripture Guide**
- Copy verse
- Share verse
- Save to favorites
- Add note
- View in different translation

### 5. **Prayer Wall**
- Commit to pray
- Share prayer request
- Copy for personal prayer
- Mark as answered

## Best Practices

1. **Always prevent default**: `e.preventDefault()` to stop browser menu
2. **Position awareness**: Adjust menu position near screen edges
3. **Click outside to close**: Add document click listener
4. **Escape key to close**: Add keyboard listener
5. **Mobile support**: Add long-press for touch devices
6. **Accessibility**: Ensure keyboard navigation works
7. **Visual feedback**: Show hover states and animations

## CSS Variables for Theming

```css
:root {
  --context-menu-bg: rgba(26, 26, 46, 0.98);
  --context-menu-border: var(--border-gold);
  --context-menu-hover: rgba(255, 215, 0, 0.1);
  --context-menu-text: var(--text-light);
  --context-menu-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
}
```

This context menu system integrates perfectly with your Illuminated Sanctuary theme!