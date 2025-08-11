<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  export let show = false;
  
  let activeTab: 'my-groups' | 'discover' | 'create' | 'invites' = 'my-groups';
  let myGroups: any[] = [];
  let myInvites: any[] = [];
  let publicGroups: any[] = [];
  let loading = false;
  
  // Create group form
  let groupName = '';
  let groupDescription = '';
  let groupType = 'general';
  let isPrivate = false;
  let selectedMembers: Set<string> = new Set();
  let fellowshipMembers: any[] = [];
  let searchTerm = '';
  
  // Group management
  let selectedGroup: any = null;
  let groupPosts: any[] = [];
  let groupMembers: any[] = [];
  let newPostContent = '';
  let showMemberSelect = false;
  let showAddMembers = false;
  
  onMount(() => {
    if (show) {
      loadMyGroups();
      loadInvites();
      loadFellowshipMembers();
      loadPublicGroups();
    }
  });
  
  async function loadMyGroups() {
    loading = true;
    const user = await authStore.getUser();
    if (!user) return;
    
    console.log('Loading groups for user:', user.id);
    
    // Try RPC first
    const { data, error } = await supabase
      .rpc('get_my_fellowship_groups');
    
    if (error) {
      console.error('Error loading groups via RPC:', error);
      
      // Fallback to direct query
      console.log('Trying direct query fallback...');
      const { data: directData, error: directError } = await supabase
        .from('fellowship_groups')
        .select(`
          *,
          fellowship_group_members!inner(
            user_id,
            role,
            is_active
          )
        `)
        .or(`created_by.eq.${user.id},fellowship_group_members.user_id.eq.${user.id}`)
        .eq('fellowship_group_members.is_active', true);
      
      if (directError) {
        console.error('Direct query also failed:', directError);
      } else {
        console.log('Direct query results:', directData);
        myGroups = directData || [];
      }
    } else {
      console.log('Groups loaded via RPC:', data);
      myGroups = data || [];
    }
    
    loading = false;
  }
  
  async function loadInvites() {
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data } = await supabase
      .from('fellowship_group_invites')
      .select(`
        *,
        group:fellowship_groups(name, description, group_type),
        inviter:auth.users!invited_by(email)
      `)
      .eq('invited_user_id', user.id)
      .eq('status', 'pending')
      .gte('expires_at', new Date().toISOString());
    
    myInvites = data || [];
  }
  
  async function loadPublicGroups() {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Get public groups from fellowship members that user is not already in
    const { data, error } = await supabase
      .from('fellowship_groups')
      .select(`
        id,
        name,
        description,
        group_type,
        created_by,
        created_at,
        user_profiles!created_by (
          display_name
        )
      `)
      .eq('is_private', false)
      .order('created_at', { ascending: false });
    
    if (error) {
      console.error('Error loading public groups:', error);
    } else if (data) {
      // Filter out groups user is already a member of
      const { data: myMemberships } = await supabase
        .from('fellowship_group_members')
        .select('group_id')
        .eq('user_id', user.id)
        .eq('is_active', true);
      
      const myGroupIds = myMemberships?.map(m => m.group_id) || [];
      publicGroups = data.filter(g => !myGroupIds.includes(g.id));
      
      // Get member counts for each group
      for (const group of publicGroups) {
        const { count } = await supabase
          .from('fellowship_group_members')
          .select('*', { count: 'exact', head: true })
          .eq('group_id', group.id)
          .eq('is_active', true);
        
        group.member_count = count || 0;
      }
    }
  }
  
  async function joinPublicGroup(groupId: string) {
    const user = await authStore.getUser();
    if (!user) return;
    
    loading = true;
    
    // Add user as member
    const { error } = await supabase
      .from('fellowship_group_members')
      .insert({
        group_id: groupId,
        user_id: user.id,
        role: 'member',
        is_active: true
      });
    
    if (error) {
      console.error('Error joining group:', error);
      alert('Failed to join group');
    } else {
      alert('Successfully joined group!');
      await loadMyGroups();
      await loadPublicGroups();
      activeTab = 'my-groups';
    }
    
    loading = false;
  }
  
  async function loadFellowshipMembers() {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Get all fellowship members using RPC function
    const { data, error } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowship members:', error);
      // Fallback to direct query
      const { data: fallbackData } = await supabase
        .from('fellowships')
        .select(`
          fellow_id,
          user_profiles!fellow_id (
            display_name
          )
        `)
        .eq('user_id', user.id);
      
      if (fallbackData) {
        fellowshipMembers = fallbackData.map(f => ({
          fellow_id: f.fellow_id,
          fellow_name: f.user_profiles?.display_name || 'Unknown'
        }));
      }
    } else if (data) {
      fellowshipMembers = data;
      console.log('Loaded fellowship members:', fellowshipMembers);
    }
  }
  
  async function createGroup() {
    console.log('=== START: Create Group Process ===');
    console.log('Create group button clicked');
    console.log('Group name:', groupName);
    console.log('Group description:', groupDescription);
    console.log('Group type:', groupType);
    console.log('Is private:', isPrivate);
    
    if (!groupName.trim()) {
      alert('Please enter a group name');
      return;
    }
    
    const user = await authStore.getUser();
    console.log('Current user:', user);
    console.log('User ID:', user?.id);
    if (!user) {
      alert('You must be logged in to create a group');
      return;
    }
    
    loading = true;
    const params = {
      p_name: groupName,
      p_description: groupDescription,
      p_group_type: groupType,
      p_is_private: isPrivate
    };
    console.log('RPC Parameters:', params);
    
    // First, let's check if the function exists
    console.log('Attempting to call create_fellowship_group RPC...');
    
    // Create the group (try safe version first if main fails)
    let { data, error } = await supabase
      .rpc('create_fellowship_group', params);
    
    console.log('Initial RPC response:', { 
      data, 
      error, 
      errorMessage: error?.message,
      errorCode: error?.code,
      errorDetails: error?.details
    });
    
    // If the main function fails with ambiguous error or function doesn't exist, try the safe version
    if (error && (
        error.message?.includes('ambiguous') || 
        error.message?.includes('does not exist') ||
        error.message?.includes('No function matches') ||
        error.code === '42883'
    )) {
      console.log('Main function failed, trying safe version...');
      console.log('Error was:', error.message);
      
      const safeResult = await supabase
        .rpc('create_fellowship_group_safe', params);
      
      data = safeResult.data;
      error = safeResult.error;
      
      console.log('Safe version response:', { 
        data, 
        error,
        errorMessage: error?.message,
        errorCode: error?.code
      });
    }
    
    console.log('Final RPC response:', { data, error });
    
    if (error) {
      console.error('=== ERROR: Group creation failed ===');
      console.error('Error object:', error);
      console.error('Error message:', error.message);
      console.error('Error code:', error.code);
      alert(`Failed to create group: ${error.message}`);
    } else if (data && data[0]) {
      const result = data[0];
      console.log('Group creation result object:', result);
      console.log('Result success:', result.success);
      console.log('Result group_id:', result.group_id);
      console.log('Result message:', result.message);
      
      if (result.success && result.group_id) {
        console.log('Group created successfully with ID:', result.group_id);
        
        // Invite selected members
        if (selectedMembers.size > 0) {
          const memberIds = Array.from(selectedMembers);
          console.log('Inviting members:', memberIds);
          const { data: inviteData, error: inviteError } = await supabase
            .rpc('invite_to_fellowship_group', {
              p_group_id: result.group_id,
              p_user_ids: memberIds,
              p_message: `You've been invited to join ${groupName}`
            });
          
          console.log('Invite response:', { inviteData, inviteError });
          
          if (inviteError) {
            console.error('Error inviting members:', inviteError);
          } else {
            console.log('Members invited successfully');
          }
        }
        
        alert('Group created successfully!');
        
        // Reset form
        console.log('Resetting form...');
        groupName = '';
        groupDescription = '';
        groupType = 'general';
        isPrivate = false;
        selectedMembers.clear();
        
        // Reload groups and switch to my groups tab
        console.log('Reloading groups...');
        await loadMyGroups();
        activeTab = 'my-groups';
        console.log('=== END: Group creation complete ===');
      } else {
        console.log('Group creation returned false success');
        alert(result.message || 'Failed to create group');
      }
    } else if (data === null) {
      console.log('=== WARNING: RPC returned null data ===');
      console.log('This might mean the function executed but returned nothing');
      alert('Group creation may have succeeded - please refresh to check');
    } else {
      console.log('=== WARNING: Unexpected response format ===');
      console.log('Data:', data);
      console.log('Data type:', typeof data);
      console.log('Is array:', Array.isArray(data));
      alert('Failed to create group - unexpected response');
    }
    
    loading = false;
    console.log('=== END: Create Group Process ===');
  }
  
  async function respondToInvite(inviteId: string, response: 'accepted' | 'declined') {
    const { data, error } = await supabase
      .rpc('respond_to_group_invite', {
        p_invite_id: inviteId,
        p_response: response
      });
    
    if (error) {
      console.error('Error responding to invite:', error);
      alert('Failed to respond to invite');
    } else {
      await loadInvites();
      if (response === 'accepted') {
        await loadMyGroups();
        activeTab = 'my-groups';
      }
    }
  }
  
  async function loadGroupPosts(groupId: string) {
    const { data } = await supabase
      .from('fellowship_group_posts')
      .select('*')
      .eq('group_id', groupId)
      .order('created_at', { ascending: false })
      .limit(20);
    
    groupPosts = data || [];
  }
  
  async function loadGroupMembers(groupId: string) {
    const { data } = await supabase
      .from('fellowship_group_members')
      .select(`
        user_id,
        role,
        joined_at,
        user_profiles!user_id (
          display_name
        )
      `)
      .eq('group_id', groupId)
      .eq('is_active', true);
    
    groupMembers = data || [];
  }
  
  async function addMembersToGroup() {
    if (!selectedGroup || selectedMembers.size === 0) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const memberIds = Array.from(selectedMembers);
    const { data, error } = await supabase
      .rpc('invite_to_fellowship_group', {
        p_group_id: selectedGroup.group_id,
        p_user_ids: memberIds,
        p_message: `You've been invited to join ${selectedGroup.group_name}`
      });
    
    if (error) {
      console.error('Error inviting members:', error);
      alert('Failed to invite members');
    } else {
      alert('Members invited successfully!');
      selectedMembers.clear();
      showAddMembers = false;
      await loadGroupMembers(selectedGroup.group_id);
    }
  }
  
  async function postToGroup() {
    if (!newPostContent.trim() || !selectedGroup) return;
    
    const user = await authStore.getUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('fellowship_group_posts')
      .insert({
        group_id: selectedGroup.group_id,
        user_id: user.id,
        user_name: user.user_metadata?.name || user.email?.split('@')[0] || 'Anonymous',
        content: newPostContent,
        post_type: 'general'
      });
    
    if (!error) {
      newPostContent = '';
      await loadGroupPosts(selectedGroup.group_id);
    }
  }
  
  function toggleMember(memberId: string) {
    if (selectedMembers.has(memberId)) {
      selectedMembers.delete(memberId);
    } else {
      selectedMembers.add(memberId);
    }
    selectedMembers = selectedMembers;
  }
  
  function selectGroup(group: any) {
    selectedGroup = group;
    loadGroupPosts(group.group_id);
    loadGroupMembers(group.group_id);
  }
  
  function formatDate(dateString: string) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / 86400000);
    
    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    return date.toLocaleDateString();
  }
  
  $: filteredMembers = fellowshipMembers.filter(m => 
    searchTerm ? m.fellow_name.toLowerCase().includes(searchTerm.toLowerCase()) : true
  );
</script>

{#if show}
  <div class="groups-overlay" on:click={() => show = false}>
    <div class="groups-modal" on:click|stopPropagation>
      <div class="modal-header">
        <h2>🏛️ Fellowship Groups</h2>
        <button class="close-btn" on:click={() => show = false}>✕</button>
      </div>
      
      <div class="tab-nav">
        <button 
          class="tab-btn {activeTab === 'my-groups' ? 'active' : ''}"
          on:click={() => activeTab = 'my-groups'}
        >
          My Groups ({myGroups.length})
        </button>
        <button 
          class="tab-btn {activeTab === 'discover' ? 'active' : ''}"
          on:click={() => activeTab = 'discover'}
        >
          Discover {#if publicGroups.length > 0}({publicGroups.length}){/if}
        </button>
        <button 
          class="tab-btn {activeTab === 'create' ? 'active' : ''}"
          on:click={() => activeTab = 'create'}
        >
          Create Group
        </button>
        <button 
          class="tab-btn {activeTab === 'invites' ? 'active' : ''}"
          on:click={() => activeTab = 'invites'}
        >
          Invites {#if myInvites.length > 0}({myInvites.length}){/if}
        </button>
      </div>
      
      <div class="modal-content">
        {#if activeTab === 'my-groups'}
          {#if loading}
            <div class="loading">Loading groups...</div>
          {:else if myGroups.length === 0}
            <div class="empty">
              <p>You're not part of any groups yet</p>
              <p class="hint">Create a group or wait for an invitation</p>
            </div>
          {:else}
            <div class="groups-grid">
              {#each myGroups as group}
                <div 
                  class="group-card"
                  class:selected={selectedGroup?.group_id === group.group_id}
                  on:click={() => selectGroup(group)}
                >
                  <div class="group-header">
                    <div class="group-icon">
                      {#if group.group_type === 'mens'}
                        👔
                      {:else if group.group_type === 'womens'}
                        👗
                      {:else if group.group_type === 'bible_study'}
                        📖
                      {:else if group.group_type === 'prayer'}
                        🙏
                      {:else if group.group_type === 'youth'}
                        🎮
                      {:else}
                        👥
                      {/if}
                    </div>
                    <div class="group-info">
                      <h3>{group.group_name}</h3>
                      <p class="group-meta">
                        {group.member_count} members • {group.my_role}
                      </p>
                    </div>
                  </div>
                  {#if group.description}
                    <p class="group-description">{group.description}</p>
                  {/if}
                </div>
              {/each}
            </div>
            
            {#if selectedGroup}
              <div class="group-detail">
                <div class="group-detail-header">
                  <h3>{selectedGroup.group_name} - Activity</h3>
                  {#if selectedGroup.my_role === 'admin'}
                    <button 
                      class="manage-btn"
                      on:click={() => showAddMembers = !showAddMembers}
                    >
                      {showAddMembers ? 'Hide' : '➕ Add Members'}
                    </button>
                  {/if}
                </div>
                
                {#if showAddMembers && selectedGroup.my_role === 'admin'}
                  <div class="add-members-section">
                    <h4>Add Fellowship Members to Group</h4>
                    <div class="member-selector">
                      <input
                        type="text"
                        placeholder="Search fellowship members..."
                        bind:value={searchTerm}
                        class="member-search"
                      />
                      <div class="members-list">
                        {#each filteredMembers as member}
                          <label class="member-item">
                            <input
                              type="checkbox"
                              checked={selectedMembers.has(member.fellow_id)}
                              on:change={() => toggleMember(member.fellow_id)}
                            />
                            <span>{member.fellow_name}</span>
                          </label>
                        {/each}
                      </div>
                      <button 
                        class="add-members-btn"
                        on:click={addMembersToGroup}
                        disabled={selectedMembers.size === 0}
                      >
                        Invite {selectedMembers.size} Member{selectedMembers.size !== 1 ? 's' : ''}
                      </button>
                    </div>
                  </div>
                {/if}
                
                <div class="group-members-list">
                  <h4>Members ({groupMembers.length})</h4>
                  <div class="members-grid">
                    {#each groupMembers as member}
                      <div class="member-badge">
                        <span class="member-name">
                          {member.user_profiles?.display_name || 'Unknown'}
                        </span>
                        {#if member.role === 'admin'}
                          <span class="admin-badge">Admin</span>
                        {/if}
                      </div>
                    {/each}
                  </div>
                </div>
                
                <div class="post-input">
                  <textarea
                    bind:value={newPostContent}
                    placeholder="Share with the group..."
                    rows="2"
                  />
                  <button 
                    class="post-btn"
                    on:click={postToGroup}
                    disabled={!newPostContent.trim()}
                  >
                    Post
                  </button>
                </div>
                
                <div class="group-posts">
                  {#if groupPosts.length === 0}
                    <p class="no-posts">No posts yet. Be the first to share!</p>
                  {:else}
                    {#each groupPosts as post}
                      <div class="group-post">
                        <div class="post-header">
                          <span class="post-author">{post.user_name}</span>
                          <span class="post-time">{formatDate(post.created_at)}</span>
                        </div>
                        <p class="post-content">{post.content}</p>
                      </div>
                    {/each}
                  {/if}
                </div>
              </div>
            {/if}
          {/if}
          
        {:else if activeTab === 'discover'}
          {#if loading}
            <div class="loading">Loading public groups...</div>
          {:else if publicGroups.length === 0}
            <div class="empty">
              <p>No public groups available to join</p>
              <p class="hint">Public groups created by fellowship members will appear here</p>
            </div>
          {:else}
            <div class="discover-intro">
              <p>🌟 Join public groups created by your fellowship members</p>
            </div>
            <div class="groups-grid">
              {#each publicGroups as group}
                <div class="group-card discover-card">
                  <div class="group-header">
                    <div class="group-icon">
                      {#if group.group_type === 'mens'}
                        👔
                      {:else if group.group_type === 'womens'}
                        👗
                      {:else if group.group_type === 'bible_study'}
                        📖
                      {:else if group.group_type === 'prayer'}
                        🙏
                      {:else if group.group_type === 'youth'}
                        🎮
                      {:else}
                        👥
                      {/if}
                    </div>
                    <div class="group-info">
                      <h3>{group.name}</h3>
                      <p class="group-meta">
                        {group.member_count} member{group.member_count !== 1 ? 's' : ''} • 
                        Created by {group.user_profiles?.display_name || 'Unknown'}
                      </p>
                    </div>
                  </div>
                  {#if group.description}
                    <p class="group-description">{group.description}</p>
                  {/if}
                  <div class="group-actions">
                    <button 
                      class="join-btn"
                      on:click={() => joinPublicGroup(group.id)}
                      disabled={loading}
                    >
                      Join Group
                    </button>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
          
        {:else if activeTab === 'create'}
          <div class="create-group-form">
            <div class="form-group">
              <label for="group-name">Group Name *</label>
              <input
                id="group-name"
                type="text"
                bind:value={groupName}
                placeholder="e.g., Men's Bible Study"
                maxlength="100"
              />
            </div>
            
            <div class="form-group">
              <label for="group-desc">Description</label>
              <textarea
                id="group-desc"
                bind:value={groupDescription}
                placeholder="What is this group about?"
                rows="3"
              />
            </div>
            
            <div class="form-group">
              <label for="group-type">Group Type</label>
              <select id="group-type" bind:value={groupType}>
                <option value="general">General Fellowship</option>
                <option value="mens">Men's Group</option>
                <option value="womens">Women's Group</option>
                <option value="bible_study">Bible Study</option>
                <option value="prayer">Prayer Group</option>
                <option value="youth">Youth Group</option>
              </select>
            </div>
            
            <div class="form-group checkbox">
              <label>
                <input type="checkbox" bind:checked={isPrivate} />
                Private Group (invitation only)
              </label>
              <p class="form-hint">
                {#if isPrivate}
                  ✅ Only invited members can join this group
                {:else}
                  📢 This group will be visible to all fellowship members in the Discover tab
                {/if}
              </p>
            </div>
            
            <div class="form-group">
              <label>Invite Fellowship Members</label>
              <button 
                class="select-members-btn"
                on:click={() => showMemberSelect = !showMemberSelect}
              >
                {selectedMembers.size === 0 
                  ? 'Select Members to Invite' 
                  : `${selectedMembers.size} Members Selected`}
              </button>
              
              {#if showMemberSelect}
                <div class="member-selector">
                  <input
                    type="text"
                    placeholder="Search members..."
                    bind:value={searchTerm}
                    class="member-search"
                  />
                  <div class="members-list">
                    {#each filteredMembers as member}
                      <label class="member-item">
                        <input
                          type="checkbox"
                          checked={selectedMembers.has(member.fellow_id)}
                          on:change={() => toggleMember(member.fellow_id)}
                        />
                        <span>{member.fellow_name}</span>
                      </label>
                    {/each}
                  </div>
                </div>
              {/if}
            </div>
            
            <button 
              class="create-btn"
              on:click={createGroup}
              disabled={loading || !groupName.trim()}
            >
              {loading ? 'Creating...' : 'Create Group'}
            </button>
          </div>
          
        {:else if activeTab === 'invites'}
          {#if myInvites.length === 0}
            <div class="empty">
              <p>No pending group invitations</p>
            </div>
          {:else}
            <div class="invites-list">
              {#each myInvites as invite}
                <div class="invite-card">
                  <div class="invite-info">
                    <h4>{invite.group?.name || 'Unknown Group'}</h4>
                    {#if invite.group?.description}
                      <p class="invite-desc">{invite.group.description}</p>
                    {/if}
                    {#if invite.message}
                      <p class="invite-message">"{invite.message}"</p>
                    {/if}
                    <p class="invite-meta">
                      Invited by {invite.inviter?.email?.split('@')[0] || 'Unknown'}
                    </p>
                  </div>
                  <div class="invite-actions">
                    <button 
                      class="accept-btn"
                      on:click={() => respondToInvite(invite.id, 'accepted')}
                    >
                      Accept
                    </button>
                    <button 
                      class="decline-btn"
                      on:click={() => respondToInvite(invite.id, 'declined')}
                    >
                      Decline
                    </button>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .groups-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.8);
    backdrop-filter: blur(5px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    animation: fadeIn 0.3s ease-out;
  }
  
  .groups-modal {
    background: var(--bg-dark);
    border: 1px solid var(--border-gold);
    border-radius: 12px;
    width: 90%;
    max-width: 800px;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
  }
  
  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem;
    border-bottom: 1px solid var(--border-gold);
  }
  
  .modal-header h2 {
    margin: 0;
    color: var(--text-divine);
    font-size: 1.5rem;
  }
  
  .close-btn {
    background: none;
    border: none;
    color: var(--text-scripture);
    font-size: 1.5rem;
    cursor: pointer;
    padding: 0;
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.2s;
  }
  
  .close-btn:hover {
    color: var(--text-divine);
    transform: scale(1.1);
  }
  
  .tab-nav {
    display: flex;
    gap: 0.5rem;
    padding: 1rem 1.5rem 0;
    border-bottom: 1px solid var(--border-gold);
  }
  
  .tab-btn {
    background: transparent;
    border: none;
    color: var(--text-scripture);
    padding: 0.75rem 1rem;
    cursor: pointer;
    font-size: 0.95rem;
    transition: all 0.2s;
    border-bottom: 2px solid transparent;
    font-family: inherit;
  }
  
  .tab-btn:hover {
    color: var(--text-divine);
  }
  
  .tab-btn.active {
    color: var(--text-divine);
    border-bottom-color: var(--primary-gold);
  }
  
  .modal-content {
    flex: 1;
    overflow-y: auto;
    padding: 1.5rem;
  }
  
  .loading, .empty {
    text-align: center;
    padding: 2rem;
    color: var(--text-scripture);
  }
  
  .hint {
    font-size: 0.9rem;
    opacity: 0.8;
    margin-top: 0.5rem;
  }
  
  .groups-grid {
    display: grid;
    gap: 1rem;
    margin-bottom: 1rem;
  }
  
  .group-card {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 1rem;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .group-card:hover, .group-card.selected {
    background: rgba(255, 255, 255, 0.05);
    border-color: var(--border-gold);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.1);
  }
  
  .group-header {
    display: flex;
    gap: 1rem;
    align-items: start;
  }
  
  .group-icon {
    font-size: 2rem;
  }
  
  .group-info h3 {
    margin: 0 0 0.25rem 0;
    color: var(--text-divine);
    font-size: 1.1rem;
  }
  
  .group-meta {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin: 0;
  }
  
  .group-description {
    color: var(--text-light);
    font-size: 0.9rem;
    margin: 0.5rem 0 0 0;
    opacity: 0.9;
  }
  
  .group-detail {
    border-top: 1px solid var(--border-gold);
    padding-top: 1rem;
    margin-top: 1rem;
  }
  
  .group-detail h3 {
    color: var(--text-divine);
    margin: 0 0 1rem 0;
  }
  
  .group-detail-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }
  
  .manage-btn {
    padding: 0.5rem 1rem;
    background: rgba(138, 43, 226, 0.2);
    color: var(--text-divine);
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.9rem;
  }
  
  .manage-btn:hover {
    background: rgba(138, 43, 226, 0.3);
    transform: scale(1.05);
  }
  
  .add-members-section {
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  
  .add-members-section h4 {
    color: var(--text-divine);
    margin: 0 0 1rem 0;
    font-size: 1rem;
  }
  
  .add-members-btn {
    width: 100%;
    padding: 0.75rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 6px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    margin-top: 0.5rem;
  }
  
  .add-members-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(255, 215, 0, 0.3);
  }
  
  .add-members-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  .group-members-list {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 8px;
    padding: 1rem;
    margin-bottom: 1rem;
  }
  
  .group-members-list h4 {
    color: var(--text-divine);
    margin: 0 0 0.75rem 0;
    font-size: 0.95rem;
  }
  
  .members-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  
  .member-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.25rem 0.75rem;
    background: rgba(255, 215, 0, 0.1);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 15px;
    font-size: 0.85rem;
  }
  
  .member-name {
    color: var(--text-light);
  }
  
  .admin-badge {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    padding: 0.1rem 0.4rem;
    border-radius: 10px;
    font-size: 0.7rem;
    font-weight: 600;
  }
  
  .post-input {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
  }
  
  .post-input textarea {
    flex: 1;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    padding: 0.75rem;
    border-radius: 6px;
    font-family: inherit;
    resize: vertical;
  }
  
  .post-btn {
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 6px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .post-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(255, 215, 0, 0.3);
  }
  
  .post-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  .group-posts {
    max-height: 300px;
    overflow-y: auto;
  }
  
  .no-posts {
    text-align: center;
    color: var(--text-scripture);
    padding: 2rem;
  }
  
  .group-post {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 6px;
    padding: 0.75rem;
    margin-bottom: 0.5rem;
  }
  
  .post-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
  }
  
  .post-author {
    color: var(--text-divine);
    font-weight: 500;
    font-size: 0.9rem;
  }
  
  .post-time {
    color: var(--text-scripture);
    font-size: 0.8rem;
  }
  
  .post-content {
    color: var(--text-light);
    margin: 0;
    line-height: 1.4;
  }
  
  /* Create Group Form */
  .create-group-form {
    max-width: 500px;
    margin: 0 auto;
  }
  
  .form-group {
    margin-bottom: 1.5rem;
  }
  
  .form-group label {
    display: block;
    color: var(--text-divine);
    margin-bottom: 0.5rem;
    font-size: 0.95rem;
  }
  
  .form-group input,
  .form-group textarea,
  .form-group select {
    width: 100%;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    padding: 0.75rem;
    border-radius: 6px;
    font-family: inherit;
  }
  
  .form-group.checkbox label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
  }
  
  .form-group.checkbox input {
    width: auto;
  }
  
  .form-hint {
    font-size: 0.85rem;
    color: var(--text-scripture);
    margin: 0.5rem 0 0 1.5rem;
    opacity: 0.9;
  }
  
  .select-members-btn {
    width: 100%;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .select-members-btn:hover {
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--border-gold);
  }
  
  .member-selector {
    margin-top: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 6px;
    padding: 0.75rem;
  }
  
  .member-search {
    width: 100%;
    padding: 0.5rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    border-radius: 4px;
    margin-bottom: 0.5rem;
  }
  
  .members-list {
    max-height: 200px;
    overflow-y: auto;
  }
  
  .member-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem;
    cursor: pointer;
    color: var(--text-light);
    transition: background 0.2s;
  }
  
  .member-item:hover {
    background: rgba(255, 215, 0, 0.05);
  }
  
  .create-btn {
    width: 100%;
    padding: 1rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .create-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(255, 215, 0, 0.3);
  }
  
  .create-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  /* Invites */
  .invites-list {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  
  .invite-card {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 1rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  
  .invite-info h4 {
    margin: 0 0 0.5rem 0;
    color: var(--text-divine);
  }
  
  .invite-desc, .invite-message {
    color: var(--text-light);
    font-size: 0.9rem;
    margin: 0.25rem 0;
  }
  
  .invite-message {
    font-style: italic;
  }
  
  .invite-meta {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin: 0.5rem 0 0 0;
  }
  
  .invite-actions {
    display: flex;
    gap: 0.5rem;
  }
  
  .accept-btn, .decline-btn {
    padding: 0.5rem 1rem;
    border-radius: 6px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
    border: none;
  }
  
  .accept-btn {
    background: rgba(76, 175, 80, 0.2);
    color: #4caf50;
    border: 1px solid rgba(76, 175, 80, 0.3);
  }
  
  .accept-btn:hover {
    background: rgba(76, 175, 80, 0.3);
    transform: scale(1.05);
  }
  
  .decline-btn {
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
    border: 1px solid rgba(255, 87, 34, 0.3);
  }
  
  .decline-btn:hover {
    background: rgba(255, 87, 34, 0.3);
    transform: scale(1.05);
  }
  
  /* Discover Groups Styles */
  .discover-intro {
    text-align: center;
    padding: 1rem 0;
    color: var(--text-divine);
    border-bottom: 1px solid rgba(255, 215, 0, 0.1);
    margin-bottom: 1rem;
  }
  
  .discover-intro p {
    margin: 0;
    font-size: 1.1rem;
  }
  
  .discover-card {
    position: relative;
  }
  
  .group-actions {
    display: flex;
    justify-content: flex-end;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .join-btn {
    padding: 0.5rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 6px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.9rem;
  }
  
  .join-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(255, 215, 0, 0.3);
  }
  
  .join-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  @media (max-width: 600px) {
    .groups-modal {
      width: 95%;
      max-height: 90vh;
    }
    
    .invite-card {
      flex-direction: column;
      gap: 1rem;
    }
    
    .invite-actions {
      width: 100%;
    }
    
    .accept-btn, .decline-btn {
      flex: 1;
    }
  }
</style>