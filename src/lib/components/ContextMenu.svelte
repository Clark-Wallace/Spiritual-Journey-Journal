<script lang="ts">
  import { onMount } from 'svelte';
  
  export let x = 0;
  export let y = 0;
  export let show = false;
  export let items: Array<{
    label: string;
    icon?: string;
    action: () => void;
    divider?: boolean;
  }> = [];
  
  let menu: HTMLDivElement;
  
  onMount(() => {
    // Close menu when clicking outside
    function handleClick(e: MouseEvent) {
      if (menu && !menu.contains(e.target as Node)) {
        show = false;
      }
    }
    
    // Close menu on escape key
    function handleKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        show = false;
      }
    }
    
    document.addEventListener('click', handleClick);
    document.addEventListener('keydown', handleKeydown);
    
    return () => {
      document.removeEventListener('click', handleClick);
      document.removeEventListener('keydown', handleKeydown);
    };
  });
  
  // Adjust position to keep menu on screen
  $: if (show && menu) {
    const rect = menu.getBoundingClientRect();
    if (rect.right > window.innerWidth) {
      x = window.innerWidth - rect.width - 10;
    }
    if (rect.bottom > window.innerHeight) {
      y = window.innerHeight - rect.height - 10;
    }
  }
</script>

{#if show}
  <div 
    bind:this={menu}
    class="context-menu" 
    style="left: {x}px; top: {y}px;"
  >
    {#each items as item}
      {#if item.divider}
        <div class="divider"></div>
      {:else}
        <button 
          class="menu-item" 
          on:click={() => {
            item.action();
            show = false;
          }}
        >
          {#if item.icon}
            <span class="icon">{item.icon}</span>
          {/if}
          <span>{item.label}</span>
        </button>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .context-menu {
    position: fixed;
    background: rgba(26, 26, 46, 0.98);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    padding: 0.5rem 0;
    min-width: 180px;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
    z-index: 1000;
    backdrop-filter: blur(10px);
    animation: fadeIn 0.2s ease-out;
  }
  
  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: scale(0.95);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }
  
  .menu-item {
    width: 100%;
    padding: 0.6rem 1rem;
    background: transparent;
    border: none;
    color: var(--text-light);
    text-align: left;
    cursor: pointer;
    transition: all 0.2s;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    font-size: 0.9rem;
    font-family: inherit;
  }
  
  .menu-item:hover {
    background: rgba(255, 215, 0, 0.1);
    color: var(--text-divine);
  }
  
  .icon {
    width: 20px;
    display: inline-block;
    text-align: center;
  }
  
  .divider {
    height: 1px;
    background: var(--border-gold);
    margin: 0.25rem 0;
    opacity: 0.3;
  }
</style>