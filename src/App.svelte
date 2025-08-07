<script lang="ts">
  import { onMount } from 'svelte';
  import { currentView, journalEntries } from './lib/stores';
  import { authStore, userInfo } from './lib/stores/auth';
  import Login from './lib/components/Login.svelte';
  import JournalForm from './lib/components/JournalForm.svelte';
  import JournalList from './lib/components/JournalList.svelte';
  import StreakDisplay from './lib/components/StreakDisplay.svelte';
  import ScriptureGuide from './lib/components/ScriptureGuide.svelte';
  import CommunityFeed from './lib/components/CommunityFeed.svelte';
  import TheWay from './lib/components/TheWay.svelte';
  
  onMount(async () => {
    await authStore.initialize();
    
    // Load data if user is logged in
    authStore.subscribe(async (user) => {
      if (user) {
        await journalEntries.loadEntries();
      }
    });
  });
  
  const verses = [
    "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, to give you hope and a future. - Jeremiah 29:11",
    "Trust in the Lord with all your heart and lean not on your own understanding. - Proverbs 3:5",
    "I can do all things through Christ who strengthens me. - Philippians 4:13",
    "The Lord is my shepherd; I shall not want. - Psalm 23:1",
    "Be still, and know that I am God. - Psalm 46:10"
  ];
  
  const verseOfDay = verses[Math.floor(Math.random() * verses.length)];
</script>

{#if !$authStore}
  <Login />
{:else}
<main>
  <header>
    <div class="header-content">
      <div>
        <h1>🕊️ Spiritual Journey Journal</h1>
        <p class="tagline">Welcome, {$userInfo?.name}!</p>
      </div>
      <button class="logout-btn" on:click={() => authStore.signOut()}>
        Sign Out
      </button>
    </div>
  </header>
  
  <nav>
    <button 
      class:active={$currentView === 'home'} 
      on:click={() => $currentView = 'home'}
    >
      🏠 Home
    </button>
    <button 
      class:active={$currentView === 'community'} 
      on:click={() => $currentView = 'community'}
    >
      🌍 Community
    </button>
    <button 
      class:active={$currentView === 'journal'} 
      on:click={() => $currentView = 'journal'}
    >
      📔 Journal
    </button>
    <button 
      class:active={$currentView === 'guidance'} 
      on:click={() => $currentView = 'guidance'}
    >
      ✨ Guidance
    </button>
    <button 
      class:active={$currentView === 'theway'} 
      on:click={() => $currentView = 'theway'}
    >
      💬 The Way
    </button>
  </nav>
  
  <div class="content">
    {#if $currentView === 'home'}
      <div class="home-view">
        <div class="verse-card">
          <h2>Today's Verse</h2>
          <p class="verse">{verseOfDay}</p>
        </div>
        
        <StreakDisplay />
        
        <div class="quick-actions">
          <button class="action-btn" on:click={() => $currentView = 'journal'}>
            ✍️ New Journal Entry
          </button>
        </div>
        
        <JournalList />
      </div>
    {:else if $currentView === 'journal'}
      <JournalForm />
      <hr />
      <JournalList />
    {:else if $currentView === 'guidance'}
      <ScriptureGuide />
    {:else if $currentView === 'community'}
      <CommunityFeed />
    {:else if $currentView === 'theway'}
      <TheWay />
    {/if}
  </div>
</main>
{/if}

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    background: #f5f7fa;
    color: #333;
  }
  
  :global(*) {
    box-sizing: border-box;
  }
  
  main {
    min-height: 100vh;
  }
  
  header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 1.5rem;
  }
  
  .header-content {
    max-width: 800px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  
  header h1 {
    margin: 0;
    font-size: 1.8rem;
  }
  
  .tagline {
    margin: 0.5rem 0 0;
    opacity: 0.9;
    font-size: 0.9rem;
  }
  
  .logout-btn {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.2);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.875rem;
    transition: background 0.2s;
  }
  
  .logout-btn:hover {
    background: rgba(255, 255, 255, 0.3);
  }
  
  nav {
    background: white;
    border-bottom: 1px solid #e0e0e0;
    display: flex;
    justify-content: center;
    gap: 1rem;
    padding: 0.5rem;
    position: sticky;
    top: 0;
    z-index: 100;
  }
  
  nav button {
    padding: 0.5rem 1rem;
    border: none;
    background: transparent;
    cursor: pointer;
    font-size: 1rem;
    border-radius: 4px;
    transition: all 0.2s;
  }
  
  nav button:hover {
    background: #f0f0f0;
  }
  
  nav button.active {
    background: #4a90e2;
    color: white;
  }
  
  .content {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .verse-card {
    background: white;
    padding: 1.5rem;
    border-radius: 8px;
    margin-bottom: 1.5rem;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
  
  .verse-card h2 {
    margin: 0 0 0.75rem 0;
    color: #4a90e2;
    font-size: 1.2rem;
  }
  
  .verse {
    font-style: italic;
    line-height: 1.6;
    color: #555;
  }
  
  .quick-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    margin-bottom: 1.5rem;
  }
  
  .action-btn {
    padding: 1rem;
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: transform 0.2s;
    background: #4a90e2;
    color: white;
  }
  
  .action-btn:hover {
    transform: translateY(-2px);
  }
  
  .action-btn.secondary {
    background: #27ae60;
  }
  
  hr {
    border: none;
    border-top: 1px solid #e0e0e0;
    margin: 2rem 0;
  }
  
  @media (max-width: 600px) {
    .quick-actions {
      grid-template-columns: 1fr;
    }
  }
</style>
