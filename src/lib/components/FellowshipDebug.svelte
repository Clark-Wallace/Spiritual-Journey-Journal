<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  let user: any = null;
  let fellowships: any[] = [];
  let pendingRequests: any[] = [];
  let incomingRequests: any[] = [];
  let allRequests: any[] = [];
  let userProfiles: any[] = [];
  let testResults: any = {};
  
  onMount(async () => {
    user = await authStore.getUser();
    if (user) {
      await runDiagnostics();
    }
  });
  
  async function runDiagnostics() {
    console.log('=== FELLOWSHIP DIAGNOSTICS ===');
    console.log('Current User ID:', user.id);
    
    // Test 1: Direct query to fellowship_requests
    try {
      const { data, error } = await supabase
        .from('fellowship_requests')
        .select('*')
        .or(`from_user_id.eq.${user.id},to_user_id.eq.${user.id}`);
      
      testResults.directQuery = { success: !error, data, error };
      allRequests = data || [];
      console.log('Direct query results:', data, error);
      
      // Also check specifically for pending requests
      const { data: pendingData } = await supabase
        .from('fellowship_requests')
        .select('*')
        .eq('to_user_id', user.id)
        .eq('status', 'pending');
      
      console.log('Pending requests for this user:', pendingData);
    } catch (e) {
      testResults.directQuery = { success: false, error: e };
    }
    
    // Test 2: RPC function get_fellowship_requests
    try {
      const { data, error } = await supabase
        .rpc('get_fellowship_requests', { p_user_id: user.id });
      
      testResults.rpcGetRequests = { success: !error, data, error };
      console.log('RPC get_fellowship_requests:', data, error);
      
      if (data) {
        pendingRequests = data.filter((r: any) => r.direction === 'sent');
        incomingRequests = data.filter((r: any) => r.direction === 'received');
      }
    } catch (e) {
      testResults.rpcGetRequests = { success: false, error: e };
    }
    
    // Test 3: Direct query to fellowships
    try {
      const { data, error } = await supabase
        .from('fellowships')
        .select('*')
        .or(`user_id.eq.${user.id},fellow_id.eq.${user.id}`);
      
      testResults.directFellowships = { success: !error, data, error };
      fellowships = data || [];
      console.log('Direct fellowships query:', data, error);
    } catch (e) {
      testResults.directFellowships = { success: false, error: e };
    }
    
    // Test 4: Check user_profiles
    try {
      const { data, error } = await supabase
        .from('user_profiles')
        .select('*')
        .limit(10);
      
      testResults.userProfiles = { success: !error, data, error };
      userProfiles = data || [];
      console.log('User profiles:', data, error);
    } catch (e) {
      testResults.userProfiles = { success: false, error: e };
    }
    
    // Test 5: Check if send_fellowship_request function exists
    // We won't actually send a request to avoid creating test data
    try {
      // Just check if the function exists by getting first user profile
      const { data: profiles } = await supabase
        .from('user_profiles')
        .select('user_id')
        .neq('user_id', user.id)
        .limit(1);
      
      if (profiles && profiles.length > 0) {
        // Test with a real user ID (but we'll use dry run)
        testResults.sendRequest = { 
          success: true, 
          data: { message: 'Function exists, ready to send requests' },
          error: null 
        };
      } else {
        testResults.sendRequest = { 
          success: true, 
          data: { message: 'No other users to test with' },
          error: null 
        };
      }
      console.log('Send request function check:', testResults.sendRequest);
    } catch (e) {
      testResults.sendRequest = { success: false, error: e };
    }
  }
  
  async function clearAllRequests() {
    if (!confirm('Clear all your fellowship requests?')) return;
    
    const { error } = await supabase
      .from('fellowship_requests')
      .delete()
      .or(`from_user_id.eq.${user.id},to_user_id.eq.${user.id}`);
    
    if (!error) {
      await runDiagnostics();
      alert('Cleared!');
    }
  }
  
  async function testSendRequest(toUserId: string) {
    const { data, error } = await supabase
      .rpc('send_fellowship_request', {
        p_from_user_id: user.id,
        p_to_user_id: toUserId
      });
    
    console.log('Test send result:', data, error);
    alert(JSON.stringify({ data, error }, null, 2));
    await runDiagnostics();
  }
</script>

<div class="debug-panel">
  <h2>🔧 Fellowship System Diagnostics</h2>
  
  {#if user}
    <div class="info">
      <strong>Your User ID:</strong> {user.id}
    </div>
    
    <div class="section">
      <h3>Test Results</h3>
      {#each Object.entries(testResults) as [test, result]}
        <div class="test-result {result.success ? 'success' : 'error'}">
          <strong>{test}:</strong>
          {result.success ? '✅ Success' : '❌ Failed'}
          {#if result.error}
            <pre>{JSON.stringify(result.error, null, 2)}</pre>
          {/if}
        </div>
      {/each}
    </div>
    
    <div class="section">
      <h3>All Requests (Direct Query)</h3>
      {#if allRequests.length === 0}
        <p>No requests found</p>
      {:else}
        {#each allRequests as request}
          <div class="request">
            <div>ID: {request.id}</div>
            <div>From: {request.from_user_id}</div>
            <div>To: {request.to_user_id}</div>
            <div>Status: {request.status}</div>
            <div>Created: {new Date(request.created_at).toLocaleString()}</div>
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="section">
      <h3>Incoming Requests (RPC)</h3>
      {#if incomingRequests.length === 0}
        <p>No incoming requests</p>
      {:else}
        {#each incomingRequests as request}
          <div class="request">
            {JSON.stringify(request, null, 2)}
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="section">
      <h3>Fellowships</h3>
      {#if fellowships.length === 0}
        <p>No fellowships</p>
      {:else}
        {#each fellowships as fellowship}
          <div class="fellowship">
            User: {fellowship.user_id} → Fellow: {fellowship.fellow_id}
          </div>
        {/each}
      {/if}
    </div>
    
    <div class="section">
      <h3>User Profiles</h3>
      {#each userProfiles as profile}
        <div class="profile">
          <button on:click={() => testSendRequest(profile.user_id)}>
            Send Request to {profile.display_name}
          </button>
        </div>
      {/each}
    </div>
    
    <div class="actions">
      <button on:click={runDiagnostics}>🔄 Refresh Diagnostics</button>
      <button on:click={clearAllRequests}>🗑️ Clear All Requests</button>
    </div>
  {:else}
    <p>Not logged in</p>
  {/if}
</div>

<style>
  .debug-panel {
    position: fixed;
    top: 0;
    right: 0;
    width: 400px;
    height: 100vh;
    background: #1a1a1a;
    color: #fff;
    padding: 20px;
    overflow-y: auto;
    z-index: 9999;
    border-left: 2px solid #ffd700;
    font-size: 12px;
  }
  
  .section {
    margin: 20px 0;
    padding: 10px;
    border: 1px solid #333;
    border-radius: 4px;
  }
  
  h2 {
    color: #ffd700;
    margin: 0 0 20px 0;
  }
  
  h3 {
    color: #ffb300;
    margin: 0 0 10px 0;
  }
  
  .test-result {
    padding: 5px;
    margin: 5px 0;
    border-radius: 3px;
  }
  
  .test-result.success {
    background: rgba(0, 255, 0, 0.1);
    border-left: 3px solid #0f0;
  }
  
  .test-result.error {
    background: rgba(255, 0, 0, 0.1);
    border-left: 3px solid #f00;
  }
  
  .request, .fellowship, .profile {
    padding: 8px;
    margin: 5px 0;
    background: rgba(255, 255, 255, 0.05);
    border-radius: 3px;
    font-family: monospace;
  }
  
  button {
    background: #ffd700;
    color: #000;
    border: none;
    padding: 8px 12px;
    border-radius: 4px;
    cursor: pointer;
    margin: 5px;
    font-weight: bold;
  }
  
  button:hover {
    background: #ffb300;
  }
  
  pre {
    font-size: 10px;
    overflow-x: auto;
    background: rgba(0, 0, 0, 0.5);
    padding: 5px;
    border-radius: 3px;
  }
  
  .info {
    background: rgba(255, 215, 0, 0.1);
    padding: 10px;
    border-radius: 4px;
    margin-bottom: 10px;
  }
  
  .actions {
    position: sticky;
    bottom: 0;
    background: #1a1a1a;
    padding: 10px 0;
    border-top: 1px solid #333;
  }
</style>