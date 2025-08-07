<script lang="ts">
  // Force rebuild with Illuminated Sanctuary theme - v3 - Fullscreen chat fix
  import { onMount } from 'svelte';
  import { currentView, journalEntries } from './lib/stores';
  import { authStore, userInfo } from './lib/stores/auth';
  import Login from './lib/components/Login.svelte';
  import JournalForm from './lib/components/JournalFormIlluminated.svelte';
  import JournalList from './lib/components/JournalListIlluminated.svelte';
  import StreakDisplay from './lib/components/StreakDisplay.svelte';
  import ScriptureGuide from './lib/components/ScriptureGuide.svelte';
  import CommunityFeed from './lib/components/CommunityFeedIlluminated.svelte';
  import TheWay from './lib/components/TheWayIlluminated.svelte';
  
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
<!-- Light rays for divine atmosphere -->
<div class="light-rays">
  <div class="light-ray"></div>
  <div class="light-ray"></div>
  <div class="light-ray"></div>
  <div class="light-ray"></div>
</div>
<main>
  <header>
    <div class="header-content">
      <div>
        <h1>🕊️ Spiritual Journey</h1>
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
  
  {#if $currentView === 'theway'}
    <TheWay />
  {:else}
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
      {/if}
    </div>
  {/if}
</main>
{/if}

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: var(--font-secondary);
    background: linear-gradient(180deg, var(--bg-dark) 0%, var(--bg-dark-secondary) 100%);
    color: var(--text-light);
    position: relative;
  }
  
  :global(*) {
    box-sizing: border-box;
  }
  
  main {
    min-height: 100vh;
  }
  
  header {
    background: linear-gradient(180deg, rgba(10, 10, 15, 0.98), rgba(15, 15, 25, 0.95));
    backdrop-filter: blur(10px);
    color: var(--text-divine);
    padding: 1.5rem;
    border-bottom: 2px solid;
    border-image: linear-gradient(90deg, transparent, rgba(255, 215, 0, 0.3), transparent) 1;
    position: relative;
    z-index: 100;
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
    color: var(--text-divine);
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.5);
    font-family: var(--font-primary);
    letter-spacing: 1px;
  }
  
  header h1::before {
    content: '⛪ ';
    margin-right: 8px;
    filter: drop-shadow(0 0 10px rgba(255, 215, 0, 0.5));
  }
  
  .tagline {
    margin: 0.5rem 0 0;
    color: var(--text-holy);
    font-size: 0.9rem;
    font-style: italic;
  }
  
  .logout-btn {
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 193, 7, 0.2));
    color: var(--text-divine);
    border: 1px solid var(--border-gold);
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.875rem;
    transition: all var(--transition-normal);
  }
  
  .logout-btn:hover {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.3), rgba(255, 193, 7, 0.3));
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
    transform: translateY(-2px);
  }
  
  nav {
    background: rgba(15, 15, 30, 0.95);
    backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border-gold);
    display: flex;
    justify-content: center;
    gap: 1rem;
    padding: 0.75rem;
    position: sticky;
    top: 0;
    z-index: 99;
  }
  
  nav button {
    padding: 0.5rem 1rem;
    border: 1px solid transparent;
    background: rgba(255, 255, 255, 0.02);
    color: var(--text-holy);
    cursor: pointer;
    font-size: 1rem;
    border-radius: 8px;
    transition: all var(--transition-normal);
    font-family: var(--font-secondary);
  }
  
  nav button:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
    color: var(--text-divine);
    transform: translateY(-2px);
  }
  
  nav button.active {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.2), rgba(30, 144, 255, 0.2));
    color: var(--text-divine);
    border-color: var(--border-gold);
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.2);
  }
  
  .content {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .verse-card {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid var(--border-gold);
    padding: 1.5rem;
    border-radius: 12px;
    margin-bottom: 1.5rem;
    box-shadow: var(--shadow-card);
    backdrop-filter: blur(10px);
    position: relative;
    overflow: hidden;
  }
  
  .verse-card::before {
    content: '✨';
    position: absolute;
    top: -20px;
    right: -20px;
    font-size: 80px;
    opacity: 0.1;
    animation: float 3s ease-in-out infinite;
  }
  
  @keyframes float {
    0%, 100% { transform: translateY(0) rotate(0deg); }
    50% { transform: translateY(-10px) rotate(10deg); }
  }
  
  .verse-card h2 {
    margin: 0 0 0.75rem 0;
    color: var(--text-divine);
    font-size: 1.2rem;
    text-shadow: 0 0 10px rgba(255, 215, 0, 0.3);
    font-family: var(--font-primary);
  }
  
  .verse {
    font-style: italic;
    line-height: 1.6;
    color: var(--text-scripture);
    position: relative;
    z-index: 1;
  }
  
  .quick-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    margin-bottom: 1.5rem;
  }
  
  .action-btn {
    padding: 1rem;
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all var(--transition-normal);
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    text-shadow: none;
  }
  
  .action-btn:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow-divine-strong);
    background: linear-gradient(135deg, var(--primary-gold-light), #ffc947);
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
