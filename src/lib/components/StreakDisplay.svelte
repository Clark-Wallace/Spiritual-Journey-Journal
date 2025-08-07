<script lang="ts">
  import { streak } from '../stores';
</script>

<div class="streak-card">
  <h3>Your Journey</h3>
  
  <div class="streak-stats">
    <div class="stat">
      <div class="number">{$streak.current}</div>
      <div class="label">Current Streak</div>
    </div>
    
    <div class="stat">
      <div class="number">{$streak.longest}</div>
      <div class="label">Best Streak</div>
    </div>
    
    <div class="stat">
      <div class="number">{$streak.weeklyEntries}</div>
      <div class="label">This Week</div>
    </div>
  </div>
  
  {#if $streak.weeklyEntries < 3}
    <p class="reminder">
      ⚠️ Add {3 - $streak.weeklyEntries} more entries this week to maintain your streak!
    </p>
  {:else}
    <p class="encouragement">
      ✨ Great job! You're maintaining your spiritual practice!
    </p>
  {/if}
</div>

<style>
  .streak-card {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 1.5rem;
    border-radius: 12px;
    margin-bottom: 1.5rem;
  }
  
  h3 {
    margin: 0 0 1rem 0;
    font-size: 1.2rem;
  }
  
  .streak-stats {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .stat {
    text-align: center;
  }
  
  .number {
    font-size: 2rem;
    font-weight: bold;
  }
  
  .label {
    font-size: 0.875rem;
    opacity: 0.9;
  }
  
  .reminder, .encouragement {
    margin: 0;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.2);
    border-radius: 6px;
    font-size: 0.9rem;
  }
</style>