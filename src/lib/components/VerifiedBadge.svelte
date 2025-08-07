<script lang="ts">
  export let size: 'small' | 'medium' | 'large' = 'small';
  export let showTooltip = true;
</script>

<span class="verified-badge {size}" title={showTooltip ? "Phone Verified" : ""}>
  ✓
</span>

<style>
  .verified-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #4caf50, #45a049);
    color: white;
    border-radius: 50%;
    font-weight: bold;
    box-shadow: 0 0 10px rgba(76, 175, 80, 0.3);
    margin-left: 0.25rem;
  }
  
  .verified-badge.small {
    width: 16px;
    height: 16px;
    font-size: 10px;
  }
  
  .verified-badge.medium {
    width: 20px;
    height: 20px;
    font-size: 12px;
  }
  
  .verified-badge.large {
    width: 24px;
    height: 24px;
    font-size: 14px;
  }
  
  .verified-badge:hover {
    box-shadow: 0 0 15px rgba(76, 175, 80, 0.5);
    transform: scale(1.1);
    transition: all 0.2s;
  }
</style>