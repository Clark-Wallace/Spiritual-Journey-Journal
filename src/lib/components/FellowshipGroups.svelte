<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '../supabase';
  import { authStore } from '../stores/auth';
  
  export let show = false;
  
  let activeTab: 'my-groups' | 'create' | 'invites' = 'my-groups';
  let myGroups: any[] = [];
  let myInvites: any[] = [];
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
  let newPostContent = '';
  let showMemberSelect = false;
  
  onMount(() => {
    if (show) {
      loadMyGroups();
      loadInvites();
      loadFellowshipMembers();
    }
  });
  
  async function loadMyGroups() {
    loading = true;
    const user = await authStore.getUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('get_my_fellowship_groups');
    
    if (error) {
      console.error('Error loading groups:', error);
    } else {
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
  
  async function loadFellowshipMembers() {
    const user = await authStore.getUser();
    if (!user) return;
    
    // Get all fellowship members
    const { data } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (data) {
      fellowshipMembers = data;
    }
  }
  
  async function createGroup() {
    if (!groupName.trim()) {
      alert('Please enter a group name');
      return;
    }
    
    const user = await authStore.getUser();
    if (!user) return;
    
    loading = true;
    
    // Create the group
    const { data, error } = await supabase
      .rpc('create_fellowship_group', {
        p_name: groupName,
        p_description: groupDescription,
        p_group_type: groupType,
        p_is_private: isPrivate
      });
    
    if (error) {
      console.error('Error creating group:', error);
      alert('Failed to create group');
    } else if (data && data[0]) {
      const result = data[0];
      
      if (result.success && result.group_id) {
        // Invite selected members
        if (selectedMembers.size > 0) {
          const memberIds = Array.from(selectedMembers);
          await supabase
            .rpc('invite_to_fellowship_group', {
              p_group_id: result.group_id,
              p_user_ids: memberIds,
              p_message: `You've been invited to join ${groupName}`
            });
        }
        
        alert('Group created successfully!');
        
        // Reset form
        groupName = '';
        groupDescription = '';
        groupType = 'general';
        isPrivate = false;
        selectedMembers.clear();
        
        // Reload groups and switch to my groups tab
        await loadMyGroups();
        activeTab = 'my-groups';
      }
    }
    
    loading = false;
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
                <h3>{selectedGroup.group_name} - Activity</h3>
                
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