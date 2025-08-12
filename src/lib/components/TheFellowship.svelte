<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase, getCurrentUser } from '../supabase';
  import { authStore, userInfo } from '../stores/auth';
  
  import FellowshipGroups from './FellowshipGroups.svelte';
  
  type FellowshipView = 'feed' | 'members' | 'requests' | 'groups' | 'profile';
  
  let currentView: FellowshipView = 'feed';
  let showGroups = false;
  
  // Mood emojis mapping
  const moodEmojis: Record<string, string> = {
    grateful: '🙏',
    peaceful: '😌',
    joyful: '😊',
    hopeful: '✨',
    reflective: '🤔',
    troubled: '😟',
    anxious: '😰',
    seeking: '🔍'
  };
  let fellowships: Set<string> = new Set();
  let fellowshipMembers: any[] = [];
  let fellowshipPosts: any[] = [];
  let fellowshipRequests: any[] = [];
  let selectedProfile: any = null;
  let loading = true;
  
  // Fellowship Groups
  let myGroups: any[] = [];
  let selectedGroupId: string | null = null;
  let selectedGroupName: string = 'All Fellowship';
  let groupUnreadCounts: Record<string, number> = {};
  let groupPostsSubscription: any = null;
  let newPostContent = '';
  let newPostType: 'post' | 'prayer' | 'testimony' | 'praise' = 'post';
  let searchTerm = '';
  let searchResults: any[] = [];
  let searching = false;
  let onlineUsers: Set<string> = new Set();
  let presenceSubscription: any;
  
  onMount(async () => {
    await loadFellowships();
    await loadMyGroups();
    await loadGroupUnreadCounts();
    await loadFellowshipFeed();
    await loadFellowshipMembers();
    await loadRequests();
    setupPresenceSubscription();
    setupGroupNotifications();
    
    return () => {
      if (presenceSubscription) {
        supabase.removeChannel(presenceSubscription);
      }
      if (groupPostsSubscription) {
        supabase.removeChannel(groupPostsSubscription);
      }
    };
  });
  
  async function loadMyGroups() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('fellowship_group_members')
      .select(`
        group_id,
        role,
        fellowship_groups (
          id,
          name,
          description,
          group_type
        )
      `)
      .eq('user_id', user.id)
      .eq('is_active', true);
    
    if (!error && data) {
      myGroups = data
        .filter(m => m.fellowship_groups)
        .map(m => ({
          id: m.fellowship_groups.id,
          name: m.fellowship_groups.name,
          role: m.role,
          type: m.fellowship_groups.group_type
        }));
    }
  }
  
  async function selectGroup(groupId: string | null, groupName: string) {
    selectedGroupId = groupId;
    selectedGroupName = groupName;
    await loadFellowshipFeed();
    
    // Mark group as read when selected
    if (groupId) {
      await markGroupAsRead(groupId);
      // Clear unread count for this group
      groupUnreadCounts[groupId] = 0;
      groupUnreadCounts = groupUnreadCounts; // Trigger reactivity
    }
  }
  
  async function loadGroupUnreadCounts() {
    const user = await getCurrentUser();
    if (!user) return;
    
    try {
      const { data, error } = await supabase
        .rpc('get_group_unread_counts');
      
      if (!error && data) {
        groupUnreadCounts = {};
        data.forEach((item: any) => {
          if (item.unread_count > 0) {
            groupUnreadCounts[item.group_id] = item.unread_count;
          }
        });
      } else if (error?.code === 'PGRST202') {
        // Function doesn't exist yet, silently skip
        console.log('Group notifications not yet configured');
      }
    } catch (e) {
      // Silently handle if notifications aren't set up yet
      console.log('Group notifications not available');
    }
  }
  
  async function markGroupAsRead(groupId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    try {
      await supabase
        .rpc('mark_group_as_read', { p_group_id: groupId });
    } catch (e) {
      // Silently handle if function doesn't exist
      console.log('Mark as read not available');
    }
  }
  
  function setupGroupNotifications() {
    // Subscribe to ALL new posts (both fellowship and group posts)
    groupPostsSubscription = supabase
      .channel('fellowship-posts-channel')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'community_posts'
        },
        async (payload) => {
          const newPost = payload.new as any;
          const user = await getCurrentUser();
          
          // Don't notify for own posts
          if (newPost.user_id === user?.id) return;
          
          // Handle group posts
          if (newPost.group_id) {
            // Check if user is member of this group
            const isMember = myGroups.some(g => g.id === newPost.group_id);
            if (!isMember) return;
            
            // If this group is currently selected, refresh the feed
            if (selectedGroupId === newPost.group_id) {
              await loadFellowshipFeed();
            } else {
              // Increment unread count for this group
              groupUnreadCounts[newPost.group_id] = (groupUnreadCounts[newPost.group_id] || 0) + 1;
              groupUnreadCounts = groupUnreadCounts; // Trigger reactivity
              
              // Find group name for notification
              const group = myGroups.find(g => g.id === newPost.group_id);
              if (group) {
                // Show browser notification if permitted
                if ('Notification' in window && Notification.permission === 'granted') {
                  new Notification(`New message in ${group.name}`, {
                    body: newPost.content.substring(0, 100),
                    icon: '/favicon.ico'
                  });
                }
              }
            }
          } else if (newPost.is_fellowship_only) {
            // Handle regular fellowship posts (no group)
            if (!selectedGroupId) {
              // We're viewing "All Fellowship", refresh the feed
              await loadFellowshipFeed();
            }
          }
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'community_posts'
        },
        async (payload) => {
          // Refresh feed on updates (edits, deletions)
          const updatedPost = payload.new as any;
          
          // Check if this update is relevant to current view
          if (selectedGroupId && updatedPost.group_id === selectedGroupId) {
            await loadFellowshipFeed();
          } else if (!selectedGroupId && updatedPost.is_fellowship_only && !updatedPost.group_id) {
            await loadFellowshipFeed();
          }
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'DELETE',
          schema: 'public',
          table: 'community_posts'
        },
        async () => {
          // Refresh feed when posts are deleted
          await loadFellowshipFeed();
        }
      )
      .subscribe();
    
    // Request notification permission
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission();
    }
  }
  
  async function loadFellowships() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .from('fellowships')
      .select('fellow_id')
      .eq('user_id', user.id);
    
    if (!error && data) {
      fellowships = new Set(data.map(f => f.fellow_id));
    }
  }
  
  async function loadFellowshipMembers() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // Use the RPC function to get fellowship members with names
    const { data, error } = await supabase
      .rpc('get_fellowship_members', { for_user_id: user.id });
    
    if (error) {
      console.error('Error loading fellowship members:', error);
      // Fallback to direct query
      const { data: fallbackData } = await supabase
        .from('fellowships')
        .select('fellow_id, created_at')
        .eq('user_id', user.id);
      
      if (fallbackData && fallbackData.length > 0) {
        const memberIds = fallbackData.map(f => f.fellow_id);
        
        // Try to get names from user_profiles
        const { data: profiles } = await supabase
          .from('user_profiles')
          .select('user_id, display_name')
          .in('user_id', memberIds);
        
        const profileMap = new Map(profiles?.map(p => [p.user_id, p.display_name]) || []);
        
        fellowshipMembers = fallbackData.map(f => ({
          id: f.fellow_id,
          name: profileMap.get(f.fellow_id) || 'Unknown',
          joined: f.created_at
        }));
      }
    } else {
      fellowshipMembers = (data || []).map(member => ({
        id: member.fellow_id,
        name: member.fellow_name,
        joined: member.created_at
      }));
    }
    
    loading = false;
  }
  
  async function loadRequests() {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('get_fellowship_requests', { p_user_id: user.id });
    
    if (!error && data) {
      fellowshipRequests = data.filter((req: any) => req.direction === 'received');
    }
  }
  
  async function acceptRequest(requestId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('accept_fellowship_request', {
        p_request_id: requestId,
        p_user_id: user.id
      });
    
    if (!error) {
      await loadRequests();
      await loadFellowships();
      await loadFellowshipMembers();
      await loadFellowshipFeed();
    }
  }
  
  async function declineRequest(requestId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('decline_fellowship_request', {
        p_request_id: requestId,
        p_user_id: user.id
      });
    
    if (!error) {
      await loadRequests();
    }
  }
  
  async function loadFellowshipFeed() {
    const user = await getCurrentUser();
    if (!user) return;
    
    // If a group is selected, load group-specific posts
    if (selectedGroupId) {
      // First try using community_posts with group_id filter
      const { data, error } = await supabase
        .from('community_posts')
        .select(`
          *,
          reactions (
            id,
            reaction,
            user_id
          ),
          encouragements (
            id,
            message,
            user_name,
            created_at
          )
        `)
        .eq('group_id', selectedGroupId)
        .order('created_at', { ascending: false })
        .limit(50);
      
      if (!error && data) {
        fellowshipPosts = data;
      } else {
        fellowshipPosts = [];
      }
      return;
    }
    
    // Otherwise load general fellowship feed
    if (fellowships.size === 0) {
      await loadFellowships();
    }
    
    // Try using the RPC function first
    const { data: feedData, error: feedError } = await supabase
      .rpc('get_fellowship_feed', { for_user_id: user.id });
    
    if (feedError) {
      console.log('RPC function error, using fallback query:', feedError);
      // Fallback to direct query - check if is_fellowship_only column exists
      const fellowIds = Array.from(fellowships);
      fellowIds.push(user.id); // Include own posts
      
      if (fellowIds.length > 0) {
        // Try with is_fellowship_only first
        let { data, error } = await supabase
          .from('community_posts')
          .select(`
            *,
            reactions (
              id,
              reaction,
              user_id
            ),
            encouragements (
              id,
              message,
              user_name,
              created_at
            )
          `)
          .in('user_id', fellowIds)
          .eq('is_fellowship_only', true)  // Only get fellowship posts
          .order('created_at', { ascending: false })
          .limit(50);
        
        // If column doesn't exist, fall back to just user filter
        if (error && error.message?.includes('is_fellowship_only')) {
          console.log('is_fellowship_only column missing, using user filter only');
          const result = await supabase
            .from('community_posts')
            .select(`
              *,
              reactions (
                id,
                reaction,
                user_id
              ),
              encouragements (
                id,
                message,
                user_name,
                created_at
              )
            `)
            .in('user_id', fellowIds)
            .order('created_at', { ascending: false })
            .limit(50);
          
          data = result.data;
          error = result.error;
        }
        
        if (!error) {
          fellowshipPosts = data || [];
        }
      }
    } else {
      // Load reactions and encouragements for the posts
      const postIds = feedData.map(p => p.post_id);
      
      if (postIds.length > 0) {
        const { data: reactionsData } = await supabase
          .from('reactions')
          .select('*')
          .in('post_id', postIds);
        
        const { data: encouragementsData } = await supabase
          .from('encouragements')
          .select('*')
          .in('post_id', postIds);
        
        // Combine the data - include all fields from RPC function
        fellowshipPosts = feedData.map(post => ({
          id: post.post_id,
          user_id: post.user_id,
          user_name: post.user_name,
          content: post.content,
          mood: post.mood,  // Include mood
          gratitude: post.gratitude,  // Include gratitude
          prayer: post.prayer,  // Include prayer
          share_type: post.share_type,
          is_anonymous: post.is_anonymous,
          is_fellowship_only: post.is_fellowship_only,
          group_id: post.group_id,  // Include group_id
          group_name: post.group_name,  // Include group_name from RPC
          created_at: post.created_at,
          reactions: reactionsData?.filter(r => r.post_id === post.post_id) || [],
          encouragements: encouragementsData?.filter(e => e.post_id === post.post_id) || []
        }));
      }
    }
  }
  
  async function createPost() {
    if (!newPostContent.trim()) return;
    
    const user = await getCurrentUser();
    if (!user) return;
    
    const { error } = await supabase
      .from('community_posts')
      .insert({
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        content: newPostContent.trim(),
        share_type: newPostType,
        is_anonymous: false,
        is_fellowship_only: true,
        group_id: selectedGroupId || null  // Set group_id if a group is selected
      });
    
    if (!error) {
      newPostContent = '';
      newPostType = 'post';
      await loadFellowshipFeed();
      const message = selectedGroupId 
        ? `Post shared with ${selectedGroupName} successfully!`
        : 'Post shared with fellowship successfully!';
      console.log(message);
    } else {
      console.error('Error creating post:', error);
      alert('Failed to share post. Please try again.');
    }
  }
  
  async function viewProfile(userId: string) {
    const { data } = await supabase
      .from('community_posts')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(20);
    
    const { data: userData } = await supabase
      .from('journal_entries')
      .select('created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1);
    
    selectedProfile = {
      userId,
      posts: data || [],
      lastActive: userData?.[0]?.created_at,
      name: data?.[0]?.user_name || 'Unknown'
    };
    
    currentView = 'profile';
  }
  
  async function toggleReaction(postId: string, reactionType: string = 'amen') {
    const user = await getCurrentUser();
    if (!user) {
      console.error('No user found for reaction');
      return;
    }
    
    const post = fellowshipPosts.find(p => p.id === postId);
    if (!post) {
      console.error('Post not found:', postId);
      return;
    }
    
    console.log('Toggling reaction:', { postId, reactionType, userId: user.id });
    
    // Check if user already reacted
    const existingReaction = post.reactions?.find(
      r => r.reaction === reactionType && r.user_id === user.id
    );
    
    if (existingReaction) {
      // Remove reaction
      console.log('Removing existing reaction:', existingReaction);
      const { error } = await supabase
        .from('reactions')
        .delete()
        .eq('id', existingReaction.id);
      
      if (error) {
        console.error('Error removing reaction:', error);
        alert('Failed to remove reaction. Please try again.');
      } else {
        post.reactions = post.reactions.filter(r => r.id !== existingReaction.id);
        fellowshipPosts = fellowshipPosts; // Trigger reactivity
        console.log('Reaction removed successfully');
      }
    } else {
      // Add reaction
      console.log('Adding new reaction');
      const { data, error } = await supabase
        .from('reactions')
        .insert({
          post_id: postId,
          user_id: user.id,
          reaction: reactionType
        })
        .select()
        .single();
      
      if (error) {
        console.error('Error adding reaction:', error);
        alert('Failed to add reaction. Please try again.');
      } else if (data) {
        if (!post.reactions) post.reactions = [];
        post.reactions.push(data);
        fellowshipPosts = fellowshipPosts; // Trigger reactivity
        console.log('Reaction added successfully:', data);
      }
    }
  }
  
  let encouragementInputs: Record<string, string> = {};
  let showEncouragementInput: Record<string, boolean> = {};
  
  async function addEncouragement(postId: string) {
    const user = await getCurrentUser();
    if (!user) {
      console.error('No user found for encouragement');
      return;
    }
    
    if (!encouragementInputs[postId]?.trim()) {
      console.log('Empty encouragement message');
      return;
    }
    
    console.log('Adding encouragement:', { postId, userId: user.id, message: encouragementInputs[postId] });
    
    const { data, error } = await supabase
      .from('encouragements')
      .insert({
        post_id: postId,
        user_id: user.id,
        user_name: $userInfo?.name || user.email?.split('@')[0],
        message: encouragementInputs[postId].trim()
      })
      .select()
      .single();
    
    if (error) {
      console.error('Error adding encouragement:', error);
      alert('Failed to add encouragement. Please try again.');
    } else if (data) {
      const post = fellowshipPosts.find(p => p.id === postId);
      if (post) {
        if (!post.encouragements) post.encouragements = [];
        post.encouragements.push(data);
        fellowshipPosts = fellowshipPosts; // Trigger reactivity
      }
      encouragementInputs[postId] = '';
      showEncouragementInput[postId] = false;
      console.log('Encouragement added successfully:', data);
    }
  }
  
  async function removeFellowship(fellowId: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    if (confirm('Remove this person from your fellowship?')) {
      // Use RPC function to remove both sides
      const { data, error } = await supabase
        .rpc('remove_fellowship', {
          p_user_id: user.id,
          p_fellow_id: fellowId
        });
      
      if (error) {
        console.error('Error removing from fellowship:', error);
        // Fallback: try to remove both sides manually
        await supabase
          .from('fellowships')
          .delete()
          .eq('user_id', user.id)
          .eq('fellow_id', fellowId);
        
        await supabase
          .from('fellowships')
          .delete()
          .eq('user_id', fellowId)
          .eq('fellow_id', user.id);
      }
      
      fellowships.delete(fellowId);
      fellowships = new Set(fellowships);
      await loadFellowshipMembers();
      await loadFellowshipFeed();
    }
  }
  
  async function setupPresenceSubscription() {
    const user = await getCurrentUser();
    if (!user) return;
    
    loadOnlineUsers();
    
    presenceSubscription = supabase
      .channel('fellowship-presence-section')
      .on('postgres_changes',
        { 
          event: '*', 
          schema: 'public', 
          table: 'user_presence'
        },
        () => loadOnlineUsers()
      )
      .subscribe();
  }
  
  async function loadOnlineUsers() {
    const twoMinutesAgo = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    
    const { data, error } = await supabase
      .from('user_presence')
      .select('user_id')
      .gte('last_seen', twoMinutesAgo);
    
    if (!error && data) {
      onlineUsers = new Set(data.map(u => u.user_id));
    }
  }
  
  async function searchUsers() {
    if (!searchTerm.trim()) {
      searchResults = [];
      return;
    }
    
    searching = true;
    const user = await getCurrentUser();
    
    const { data: rpcData, error: rpcError } = await supabase
      .rpc('get_all_users_with_profiles');
    
    if (!rpcError && rpcData) {
      searchResults = (rpcData || [])
        .filter(u => u.user_id !== user?.id)
        .filter(u => !fellowships.has(u.user_id))
        .filter(u => u.display_name.toLowerCase().includes(searchTerm.toLowerCase()))
        .slice(0, 10)
        .map(u => ({
          user_id: u.user_id,
          user_name: u.display_name
        }));
    } else {
      // Fallback to searching in user_profiles table
      let { data: profileData } = await supabase
        .from('user_profiles')
        .select('user_id, display_name')
        .neq('user_id', user?.id)
        .limit(20);
      
      if (profileData) {
        searchResults = profileData
          .filter(profile => !fellowships.has(profile.user_id))
          .filter(profile => profile.display_name.toLowerCase().includes(searchTerm.toLowerCase()))
          .slice(0, 10)
          .map(profile => ({
            user_id: profile.user_id,
            user_name: profile.display_name
          }));
      }
    }
    
    searching = false;
  }
  
  async function sendFellowshipRequest(fellowId: string, fellowName: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    const { data, error } = await supabase
      .rpc('send_fellowship_request', {
        p_from_user_id: user.id,
        p_to_user_id: fellowId
      });
    
    if (error) {
      console.error('Error sending request:', error);
      const { error: insertError } = await supabase
        .from('fellowship_requests')
        .insert({
          from_user_id: user.id,
          to_user_id: fellowId,
          status: 'pending'
        });
      
      if (!insertError) {
        alert('Fellowship request sent!');
      } else {
        alert('Failed to send fellowship request');
      }
    } else if (data?.success) {
      if (data.message === 'Fellowship established (mutual request)') {
        await loadFellowships();
        await loadFellowshipMembers();
        alert('Fellowship established! They had already requested you.');
      } else {
        alert('Fellowship request sent!');
      }
    }
    
    searchTerm = '';
    searchResults = [];
  }
  
  async function startPrivateChat(userId: string, userName: string) {
    const user = await getCurrentUser();
    if (!user) return;
    
    let { data, error } = await supabase
      .rpc('send_chat_request', {
        p_from_user_id: user.id,
        p_to_user_id: userId,
        p_from_user_name: $userInfo?.name || user.email?.split('@')[0] || 'Anonymous'
      });
    
    if (error && (error.message?.includes('function') || error?.code === '42883')) {
      const directResult = await supabase
        .from('chat_requests')
        .insert({
          from_user_id: user.id,
          to_user_id: userId,
          from_user_name: $userInfo?.name || user.email?.split('@')[0] || 'Anonymous',
          status: 'pending',
          expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString()
        })
        .select()
        .single();
      
      if (!directResult.error) {
        alert(`Chat request sent to ${userName}`);
        return;
      } else if (directResult.error.message?.includes('does not exist')) {
        if (typeof window !== 'undefined' && (window as any).openPrivateChat) {
          (window as any).openPrivateChat(userId, userName);
        }
        return;
      }
    }
    
    if (!error && data && data[0]) {
      const result = data[0];
      if (result.status === 'sent') {
        alert(`Chat request sent to ${userName}`);
      } else if (result.status === 'exists') {
        alert(`Chat request already pending with ${userName}`);
      }
    }
  }
  
  function formatDate(dateString: string) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    if (days < 30) return `${Math.floor(days / 7)} weeks ago`;
    return date.toLocaleDateString();
  }
</script>

<div class="fellowship-container">
  <div class="fellowship-header">
    <h1>✨ The Fellowship ✨</h1>
    <p class="subtitle">Your spiritual family and faith journey companions</p>
  </div>
  
  <div class="fellowship-nav">
    <button 
      class:active={currentView === 'feed'}
      on:click={() => currentView = 'feed'}
    >
      📜 Fellowship Feed
    </button>
    <button 
      class:active={currentView === 'members'}
      on:click={() => currentView = 'members'}
    >
      👥 My Fellowship ({fellowshipMembers.length})
    </button>
    <button 
      class:active={currentView === 'requests'}
      on:click={() => currentView = 'requests'}
    >
      ✉️ Requests {#if fellowshipRequests.length > 0}({fellowshipRequests.length}){/if}
    </button>
    <button 
      class:active={currentView === 'groups'}
      on:click={() => { currentView = 'groups'; showGroups = true; }}
    >
      🏛️ Groups
    </button>
  </div>
  
  <!-- Group Selector Row (shown only when on feed view) -->
  {#if currentView === 'feed' && myGroups.length > 0}
    <div class="group-selector">
      <button 
        class="group-tab"
        class:active={!selectedGroupId}
        on:click={() => selectGroup(null, 'All Fellowship')}
      >
        👥 All Fellowship
      </button>
      {#each myGroups as group}
        <button 
          class="group-tab"
          class:active={selectedGroupId === group.id}
          on:click={() => selectGroup(group.id, group.name)}
        >
          {group.type === 'bible_study' ? '📖' : group.type === 'prayer' ? '🙏' : '🏛️'} {group.name}
          {#if group.role === 'admin'}
            <span class="admin-badge">👑</span>
          {/if}
          {#if groupUnreadCounts[group.id] && groupUnreadCounts[group.id] > 0}
            <span class="unread-badge">{groupUnreadCounts[group.id]}</span>
          {/if}
        </button>
      {/each}
    </div>
  {/if}
  
  <div class="fellowship-content">
    {#if currentView === 'feed'}
      <!-- Post Creator -->
      <div class="post-creator">
        <div class="creator-header">
          <h3>💬 Share with {selectedGroupName}</h3>
          <span class="creator-subtitle">Your message stays within {selectedGroupId ? 'this group' : 'your trusted circle'}</span>
        </div>
        <div class="textarea-wrapper">
          <textarea
            bind:value={newPostContent}
            placeholder="Share what God is doing in your life, ask for prayer, share encouragement..."
            rows="4"
            class="post-textarea"
            maxlength="1000"
          ></textarea>
          <div class="char-counter">{newPostContent.length}/1000</div>
        </div>
        <div class="post-controls">
          <select bind:value={newPostType} class="post-type-select">
            <option value="post">💭 General Update</option>
            <option value="prayer">🙏 Prayer Request</option>
            <option value="testimony">✨ Testimony</option>
            <option value="praise">🎉 Praise Report</option>
          </select>
          <button 
            class="post-btn" 
            on:click={createPost}
            disabled={!newPostContent.trim()}
          >
            📤 Share with Fellowship
          </button>
        </div>
      </div>
      
      <!-- Fellowship Feed -->
      {#if loading}
        <div class="loading">Loading fellowship updates...</div>
      {:else if fellowshipPosts.length === 0}
        <div class="empty-state">
          <h3>No Fellowship Posts Yet</h3>
          <p>Your fellowship feed will show posts from people in your fellowship.</p>
          <p>Add people to your fellowship from The Way chat to see their updates here!</p>
        </div>
      {:else}
        <div class="fellowship-feed">
          {#each fellowshipPosts as post}
            <div class="fellowship-post">
              <div class="post-header">
                <button 
                  class="author-link"
                  on:click={() => viewProfile(post.user_id)}
                >
                  <span class="author-avatar">
                    {post.user_name?.slice(0, 2).toUpperCase()}
                  </span>
                  <span class="author-name">
                    {post.user_name}
                    {#if post.mood && moodEmojis[post.mood]}
                      <span class="mood-status">feeling {moodEmojis[post.mood]}</span>
                    {/if}
                  </span>
                </button>
                {#if !selectedGroupId && post.group_id}
                  {@const group = myGroups.find(g => g.id === post.group_id)}
                  {#if group}
                    <button 
                      class="group-tag"
                      on:click={() => selectGroup(group.id, group.name)}
                      title="Go to {group.name}"
                    >
                      {group.type === 'bible_study' ? '📖' : group.type === 'prayer' ? '🙏' : '🏛️'} {group.name}
                    </button>
                  {/if}
                {/if}
                <span class="post-time">{formatDate(post.created_at)}</span>
              </div>
              
              {#if post.mood || post.gratitude?.length > 0}
                <div class="journal-badge">📔 Journal Entry</div>
              {/if}
              
              {#if post.share_type && post.share_type !== 'post'}
                <div class="post-type post-type-{post.share_type}">
                  {#if post.share_type === 'prayer'}
                    🙏 Prayer Request
                  {:else if post.share_type === 'testimony'}
                    ✨ Testimony
                  {:else if post.share_type === 'praise'}
                    🎉 Praise Report
                  {/if}
                </div>
              {/if}
              
              <div class="post-content">
                {post.content}
              </div>
              
              <div class="post-actions">
                <button 
                  class="action-btn"
                  class:active={post.reactions?.some(r => r.reaction === 'pray' && r.user_id === $authStore?.id)}
                  on:click={() => toggleReaction(post.id, 'pray')}
                >
                  🙏 Pray ({post.reactions?.filter(r => r.reaction === 'pray').length || 0})
                </button>
                <button 
                  class="action-btn"
                  class:active={post.reactions?.some(r => r.reaction === 'love' && r.user_id === $authStore?.id)}
                  on:click={() => toggleReaction(post.id, 'love')}
                >
                  ❤️ Love ({post.reactions?.filter(r => r.reaction === 'love').length || 0})
                </button>
                <button 
                  class="action-btn"
                  class:active={post.reactions?.some(r => r.reaction === 'amen' && r.user_id === $authStore?.id)}
                  on:click={() => toggleReaction(post.id, 'amen')}
                >
                  🙌 Amen ({post.reactions?.filter(r => r.reaction === 'amen').length || 0})
                </button>
                <button 
                  class="action-btn"
                  on:click={() => showEncouragementInput[post.id] = !showEncouragementInput[post.id]}
                >
                  💬 Encourage ({post.encouragements?.length || 0})
                </button>
              </div>
              
              {#if showEncouragementInput[post.id]}
                <div class="encouragement-input">
                  <input
                    type="text"
                    placeholder="Share an encouraging word..."
                    bind:value={encouragementInputs[post.id]}
                    on:keydown={(e) => e.key === 'Enter' && addEncouragement(post.id)}
                    class="encouragement-field"
                  />
                  <button 
                    class="send-encouragement-btn"
                    on:click={() => addEncouragement(post.id)}
                    disabled={!encouragementInputs[post.id]?.trim()}
                  >
                    Send
                  </button>
                </div>
              {/if}
              
              {#if post.encouragements?.length > 0}
                <div class="encouragements-list">
                  {#each post.encouragements as encouragement}
                    <div class="encouragement-item">
                      <strong>{encouragement.user_name}:</strong> {encouragement.message}
                    </div>
                  {/each}
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
      
    {:else if currentView === 'members'}
      <!-- Fellowship Members List -->
      <div class="members-list">
        <h3>Your Fellowship Members</h3>
        
        <!-- Search Section -->
        <div class="search-section">
          <input
            type="text"
            placeholder="Search for believers to add..."
            bind:value={searchTerm}
            on:input={searchUsers}
            class="search-input"
          />
          
          {#if searching}
            <div class="searching">Searching...</div>
          {/if}
          
          {#if searchResults.length > 0}
            <div class="search-results">
              {#each searchResults as result}
                <div class="search-result">
                  <span class="user-name">{result.user_name}</span>
                  <button 
                    class="add-btn"
                    on:click={() => sendFellowshipRequest(result.user_id, result.user_name)}
                  >
                    ➕ Send Request
                  </button>
                </div>
              {/each}
            </div>
          {/if}
        </div>
        
        {#if fellowshipMembers.length === 0}
          <div class="empty-state">
            <p>No one in your fellowship yet.</p>
            <p>Search above to send fellowship requests!</p>
          </div>
        {:else}
          {#each fellowshipMembers as member}
            <div class="member-card">
              <div class="member-avatar">
                {member.name?.slice(0, 2).toUpperCase()}
              </div>
              <div class="member-info">
                <button 
                  class="member-name"
                  on:click={() => viewProfile(member.id)}
                >
                  {member.name}
                  {#if onlineUsers.has(member.id)}
                    <span class="online-indicator" title="Online">●</span>
                  {/if}
                </button>
                <div class="member-meta">
                  Fellowship since {formatDate(member.joined)}
                </div>
              </div>
              <div class="member-actions">
                <button 
                  class="chat-btn"
                  on:click={() => startPrivateChat(member.id, member.name)}
                  title="Start private chat"
                >
                  💬
                </button>
                <button 
                  class="remove-btn"
                  on:click={() => removeFellowship(member.id)}
                  title="Remove from fellowship"
                >
                  ✕
                </button>
              </div>
            </div>
          {/each}
        {/if}
      </div>
      
    {:else if currentView === 'requests'}
      <!-- Fellowship Requests -->
      <div class="requests-section">
        <h3>Incoming Fellowship Requests</h3>
        {#if fellowshipRequests.length === 0}
          <div class="empty-state">
            <p>No pending fellowship requests.</p>
            <p>When someone sends you a fellowship request, it will appear here.</p>
          </div>
        {:else}
          {#each fellowshipRequests as request}
            <div class="request-card">
              <div class="request-info">
                <span class="requester-name">{request.from_user_name}</span>
                <span class="request-time">Requested {formatDate(request.created_at)}</span>
              </div>
              <div class="request-actions">
                <button 
                  class="accept-btn"
                  on:click={() => acceptRequest(request.request_id)}
                >
                  ✓ Accept
                </button>
                <button 
                  class="decline-btn"
                  on:click={() => declineRequest(request.request_id)}
                >
                  ✕ Decline
                </button>
              </div>
            </div>
          {/each}
        {/if}
      </div>
      
    {:else if currentView === 'groups'}
      <!-- Fellowship Groups -->
      <div class="groups-section">
        <p class="groups-description">
          Create and join fellowship groups for focused spiritual growth and community
        </p>
        <button 
          class="open-groups-btn"
          on:click={() => showGroups = true}
        >
          🏛️ Open Fellowship Groups
        </button>
      </div>
      
    {:else if currentView === 'profile' && selectedProfile}
      <!-- Profile View -->
      <div class="profile-view">
        <button class="back-btn" on:click={() => currentView = 'feed'}>
          ← Back to Feed
        </button>
        
        <div class="profile-header">
          <div class="profile-avatar">
            {selectedProfile.name?.slice(0, 2).toUpperCase()}
          </div>
          <div class="profile-info">
            <h2>{selectedProfile.name}</h2>
            {#if selectedProfile.lastActive}
              <p>Last active: {formatDate(selectedProfile.lastActive)}</p>
            {/if}
          </div>
        </div>
        
        <div class="profile-posts">
          <h3>Recent Posts</h3>
          {#each selectedProfile.posts as post}
            <div class="profile-post">
              <div class="post-date">{formatDate(post.created_at)}</div>
              <div class="post-content">{post.content}</div>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .fellowship-container {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
  }
  
  .fellowship-header {
    text-align: center;
    margin-bottom: 2rem;
    padding: 2rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(30, 144, 255, 0.1));
    border-radius: 15px;
    border: 1px solid var(--border-gold);
  }
  
  .fellowship-header h1 {
    color: var(--text-divine);
    margin: 0;
    font-size: 2.5rem;
  }
  
  .subtitle {
    color: var(--text-scripture);
    margin: 0.5rem 0 0 0;
    font-style: italic;
  }
  
  .fellowship-nav {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 2rem;
    border-bottom: 1px solid var(--border-gold);
    padding-bottom: 1rem;
  }
  
  .fellowship-nav button {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid transparent;
    color: var(--text-light);
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.3s;
  }
  
  .fellowship-nav button:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
  }
  
  .fellowship-nav button.active {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    font-weight: 600;
  }
  
  /* Group Selector Styles */
  .group-selector {
    display: flex;
    gap: 0.5rem;
    margin: 1rem 0;
    padding: 0.75rem;
    background: rgba(138, 43, 226, 0.05);
    border-radius: 10px;
    border: 1px solid rgba(138, 43, 226, 0.2);
    flex-wrap: wrap;  /* Allow wrapping to multiple rows */
  }
  
  .group-tab {
    padding: 0.5rem 1rem;
    background: var(--bg-dark);
    color: var(--text-light);
    border: 1px solid var(--border-purple);
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.3s ease;
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 0.25rem;
    flex: 0 0 auto;  /* Don't grow or shrink, maintain natural width */
  }
  
  .group-tab:hover {
    background: rgba(138, 43, 226, 0.1);
    border-color: var(--primary-color);
    transform: translateY(-1px);
  }
  
  .group-tab.active {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.3), rgba(30, 144, 255, 0.3));
    border-color: var(--primary-color-bright);
    color: var(--text-divine);
    box-shadow: 0 2px 8px rgba(138, 43, 226, 0.3);
  }
  
  .admin-badge {
    font-size: 0.8rem;
    margin-left: 0.25rem;
  }
  
  .unread-badge {
    background: linear-gradient(135deg, #ff4444, #ff6666);
    color: white;
    font-size: 0.75rem;
    font-weight: bold;
    padding: 0.1rem 0.4rem;
    border-radius: 10px;
    margin-left: 0.5rem;
    min-width: 1.2rem;
    text-align: center;
    display: inline-block;
    animation: pulse 2s infinite;
    box-shadow: 0 2px 4px rgba(255, 68, 68, 0.3);
  }
  
  @keyframes pulse {
    0% {
      transform: scale(1);
      box-shadow: 0 2px 4px rgba(255, 68, 68, 0.3);
    }
    50% {
      transform: scale(1.05);
      box-shadow: 0 2px 8px rgba(255, 68, 68, 0.5);
    }
    100% {
      transform: scale(1);
      box-shadow: 0 2px 4px rgba(255, 68, 68, 0.3);
    }
  }
  
  .group-tab:hover .unread-badge {
    animation: none;
    transform: scale(1.1);
  }
  
  .post-creator {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.08), rgba(138, 43, 226, 0.05));
    border: 2px solid var(--border-gold);
    border-radius: 16px;
    padding: 1.5rem;
    margin-bottom: 2rem;
    box-shadow: 0 4px 20px rgba(255, 215, 0, 0.1);
    position: relative;
    overflow: hidden;
  }
  
  .post-creator::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
    background: linear-gradient(90deg, var(--primary-gold), var(--primary-purple), var(--primary-gold));
    animation: shimmer 3s linear infinite;
  }
  
  @keyframes shimmer {
    0% { transform: translateX(-100%); }
    100% { transform: translateX(100%); }
  }
  
  .creator-header {
    margin-bottom: 1rem;
  }
  
  .post-creator h3 {
    color: var(--text-divine);
    margin: 0 0 0.25rem 0;
    font-size: 1.2rem;
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .creator-subtitle {
    color: var(--text-scripture);
    font-size: 0.85rem;
    font-style: italic;
  }
  
  .post-textarea {
    width: 100%;
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid rgba(255, 215, 0, 0.3);
    color: var(--text-light);
    padding: 1rem;
    border-radius: 10px;
    font-family: inherit;
    font-size: 1rem;
    resize: vertical;
    transition: all 0.3s;
  }
  
  .post-textarea:focus {
    outline: none;
    border-color: var(--border-gold);
    background: rgba(0, 0, 0, 0.5);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .post-textarea::placeholder {
    color: rgba(255, 215, 0, 0.4);
  }
  
  .textarea-wrapper {
    position: relative;
  }
  
  .char-counter {
    position: absolute;
    bottom: 10px;
    right: 10px;
    font-size: 0.75rem;
    color: var(--text-scripture);
    background: rgba(0, 0, 0, 0.6);
    padding: 0.2rem 0.5rem;
    border-radius: 4px;
  }
  
  .post-controls {
    display: flex;
    gap: 1rem;
    margin-top: 1rem;
    align-items: center;
    justify-content: space-between;
  }
  
  .post-type-select {
    padding: 0.75rem 1rem;
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid rgba(255, 215, 0, 0.3);
    color: var(--text-divine);
    border-radius: 8px;
    font-size: 0.95rem;
    cursor: pointer;
    transition: all 0.3s;
    min-width: 150px;
  }
  
  .post-type-select:hover {
    border-color: var(--border-gold);
    background: rgba(0, 0, 0, 0.5);
  }
  
  .post-type-select:focus {
    outline: none;
    border-color: var(--border-gold);
    box-shadow: 0 0 15px rgba(255, 215, 0, 0.2);
  }
  
  .post-type-select option {
    background: #1a1a2e;
    color: var(--text-divine);
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    border-radius: 6px;
  }
  
  .post-btn {
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 8px;
    font-weight: 600;
    font-size: 1rem;
    cursor: pointer;
    transition: all 0.3s;
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
  }
  
  .post-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 6px 25px rgba(255, 215, 0, 0.4);
    background: linear-gradient(135deg, #ffb300, var(--primary-gold));
  }
  
  .post-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: rgba(255, 215, 0, 0.3);
  }
  
  .fellowship-feed {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }
  
  .fellowship-post {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 12px;
    padding: 1.5rem;
    transition: all 0.3s;
  }
  
  .fellowship-post:hover {
    background: rgba(255, 255, 255, 0.05);
    border-color: var(--border-gold);
  }
  
  .post-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  
  .group-tag {
    padding: 0.25rem 0.75rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.15), rgba(30, 144, 255, 0.15));
    border: 1px solid var(--border-purple);
    border-radius: 12px;
    color: var(--text-divine);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.3s ease;
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    margin-left: auto;
    margin-right: 0.5rem;
  }
  
  .group-tag:hover {
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.3), rgba(30, 144, 255, 0.3));
    border-color: var(--primary-color-bright);
    transform: translateY(-1px);
    box-shadow: 0 2px 8px rgba(138, 43, 226, 0.3);
  }
  
  .author-link {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: none;
    color: var(--text-light);
    cursor: pointer;
    padding: 0;
    transition: all 0.2s;
  }
  
  .author-link:hover {
    color: var(--text-divine);
  }
  
  .author-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 0.9rem;
  }
  
  .author-name {
    font-weight: 600;
    color: var(--text-divine);
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .mood-status {
    font-size: 0.85rem;
    color: var(--text-scripture);
    font-weight: 400;
    font-style: italic;
    opacity: 0.9;
  }
  
  .post-time {
    color: var(--text-scripture);
    font-size: 0.85rem;
  }
  
  .post-type {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 15px;
    font-size: 0.85rem;
    margin-bottom: 0.75rem;
    font-weight: 600;
  }
  
  .post-type-prayer {
    background: rgba(138, 43, 226, 0.2);
    color: #b19cd9;
  }
  
  .post-type-testimony {
    background: rgba(255, 215, 0, 0.2);
    color: var(--text-divine);
  }
  
  .post-type-praise {
    background: rgba(76, 175, 80, 0.2);
    color: #81c784;
  }
  
  .journal-badge {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.1), rgba(255, 193, 7, 0.05));
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 10px;
    font-size: 0.7rem;
    color: var(--text-scripture);
    margin-bottom: 0.5rem;
    font-weight: 400;
    opacity: 0.8;
  }
  
  .post-content {
    color: var(--text-light);
    line-height: 1.6;
    margin-bottom: 1rem;
  }
  
  .post-actions {
    display: flex;
    gap: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .action-btn {
    padding: 0.25rem 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-scripture);
    border-radius: 15px;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 0.85rem;
  }
  
  .action-btn:hover {
    background: rgba(255, 215, 0, 0.1);
    border-color: var(--border-gold);
    color: var(--text-divine);
  }
  
  .action-btn.active {
    background: rgba(255, 215, 0, 0.15);
    border-color: var(--border-gold);
    color: var(--text-divine);
  }
  
  .encouragement-input {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .encouragement-field {
    flex: 1;
    padding: 0.5rem;
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(255, 215, 0, 0.2);
    color: var(--text-light);
    border-radius: 8px;
    font-size: 0.9rem;
  }
  
  .encouragement-field:focus {
    outline: none;
    border-color: var(--border-gold);
    background: rgba(0, 0, 0, 0.4);
  }
  
  .send-encouragement-btn {
    padding: 0.5rem 1rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 8px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .send-encouragement-btn:hover:not(:disabled) {
    transform: translateY(-1px);
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.3);
  }
  
  .send-encouragement-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  
  .encouragements-list {
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid rgba(255, 215, 0, 0.1);
  }
  
  .encouragement-item {
    padding: 0.5rem;
    background: rgba(255, 215, 0, 0.05);
    border-radius: 6px;
    margin-bottom: 0.5rem;
    font-size: 0.9rem;
    color: var(--text-light);
  }
  
  .encouragement-item strong {
    color: var(--text-divine);
  }
  
  .members-list {
    background: rgba(255, 255, 255, 0.03);
    border-radius: 12px;
    padding: 1.5rem;
  }
  
  .members-list h3 {
    color: var(--text-divine);
    margin: 0 0 1.5rem 0;
  }
  
  .member-card {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 1rem;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 215, 0, 0.1);
    border-radius: 10px;
    margin-bottom: 0.75rem;
    transition: all 0.2s;
  }
  
  .member-card:hover {
    background: rgba(255, 255, 255, 0.05);
    border-color: var(--border-gold);
  }
  
  .member-avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.3), rgba(138, 43, 226, 0.3));
    color: var(--text-divine);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
  }
  
  .member-info {
    flex: 1;
  }
  
  .member-actions {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }
  
  .chat-btn {
    padding: 0.4rem 0.8rem;
    background: rgba(138, 43, 226, 0.2);
    color: var(--text-divine);
    border: 1px solid rgba(138, 43, 226, 0.3);
    border-radius: 6px;
    font-size: 0.9rem;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .chat-btn:hover {
    background: rgba(138, 43, 226, 0.3);
    transform: scale(1.05);
    box-shadow: 0 0 10px rgba(138, 43, 226, 0.4);
  }
  
  .member-name {
    background: none;
    border: none;
    color: var(--text-divine);
    font-weight: 600;
    font-size: 1rem;
    cursor: pointer;
    padding: 0;
    text-align: left;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  
  .member-name:hover {
    text-decoration: underline;
  }
  
  .online-indicator {
    color: #4caf50;
    font-size: 0.8rem;
    animation: pulse 2s infinite;
  }
  
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
  
  .search-section {
    margin-bottom: 1.5rem;
  }
  
  .search-input {
    width: 100%;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    border-radius: 8px;
    color: var(--text-light);
    font-size: 1rem;
    font-family: inherit;
  }
  
  .search-input:focus {
    outline: none;
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--border-gold-strong);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
  }
  
  .searching {
    text-align: center;
    color: var(--text-scripture);
    padding: 1rem;
    font-style: italic;
  }
  
  .search-results {
    margin-top: 0.5rem;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 215, 0, 0.2);
    border-radius: 8px;
    padding: 0.5rem;
  }
  
  .search-result {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem;
    border-radius: 6px;
    transition: background 0.2s;
  }
  
  .search-result:hover {
    background: rgba(255, 215, 0, 0.05);
  }
  
  .user-name {
    color: var(--text-light);
  }
  
  .add-btn {
    padding: 0.25rem 0.75rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 15px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.2s;
    font-weight: 600;
  }
  
  .add-btn:hover {
    transform: scale(1.05);
    box-shadow: 0 2px 10px rgba(255, 215, 0, 0.3);
  }
  
  .member-meta {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin-top: 0.25rem;
  }
  
  .remove-btn {
    padding: 0.25rem 0.5rem;
    background: rgba(255, 87, 34, 0.2);
    color: #ff5722;
    border: 1px solid rgba(255, 87, 34, 0.3);
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s;
  }
  
  .remove-btn:hover {
    background: rgba(255, 87, 34, 0.3);
    transform: scale(1.1);
  }
  
  .empty-state {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  .empty-state h3 {
    color: var(--text-divine);
    margin-bottom: 1rem;
  }
  
  .profile-view {
    background: rgba(255, 255, 255, 0.03);
    border-radius: 12px;
    padding: 1.5rem;
  }
  
  .back-btn {
    padding: 0.5rem 1rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-gold);
    color: var(--text-light);
    border-radius: 8px;
    cursor: pointer;
    margin-bottom: 1.5rem;
  }
  
  .back-btn:hover {
    background: rgba(255, 215, 0, 0.1);
  }
  
  .profile-header {
    display: flex;
    gap: 1.5rem;
    align-items: center;
    padding-bottom: 1.5rem;
    border-bottom: 1px solid var(--border-gold);
    margin-bottom: 2rem;
  }
  
  .profile-avatar {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.4), rgba(138, 43, 226, 0.4));
    color: var(--text-divine);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    font-size: 1.5rem;
  }
  
  .profile-info h2 {
    color: var(--text-divine);
    margin: 0;
  }
  
  .profile-info p {
    color: var(--text-scripture);
    margin: 0.5rem 0 0 0;
  }
  
  .profile-posts h3 {
    color: var(--text-divine);
    margin-bottom: 1rem;
  }
  
  .profile-post {
    padding: 1rem;
    background: rgba(0, 0, 0, 0.2);
    border-left: 3px solid var(--border-gold);
    margin-bottom: 1rem;
  }
  
  .post-date {
    color: var(--text-scripture);
    font-size: 0.85rem;
    margin-bottom: 0.5rem;
  }
  
  .loading {
    text-align: center;
    padding: 3rem;
    color: var(--text-scripture);
  }
  
  @media (max-width: 600px) {
    .fellowship-container {
      padding: 0.5rem;
    }
    
    .fellowship-nav {
      flex-wrap: wrap;
    }
    
    .fellowship-nav button {
      font-size: 0.85rem;
      padding: 0.4rem 0.8rem;
    }
    
    .post-actions {
      flex-wrap: wrap;
      gap: 0.5rem;
    }
  }
  
  /* Groups Section */
  .groups-section {
    text-align: center;
    padding: 3rem 1rem;
  }
  
  .groups-description {
    color: var(--text-scripture);
    font-size: 1.1rem;
    margin-bottom: 2rem;
    max-width: 500px;
    margin-left: auto;
    margin-right: auto;
  }
  
  .open-groups-btn {
    padding: 1rem 2rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: var(--bg-dark);
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    box-shadow: 0 4px 15px rgba(255, 215, 0, 0.2);
  }
  
  .open-groups-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 25px rgba(255, 215, 0, 0.3);
  }
</style>

<!-- Fellowship Groups Modal -->
<FellowshipGroups bind:show={showGroups} />