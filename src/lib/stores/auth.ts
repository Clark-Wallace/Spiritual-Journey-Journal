import { writable, derived } from 'svelte/store';
import { supabase, signIn, signUp, signOut, getCurrentUser } from '../supabase';
import type { User } from '@supabase/supabase-js';

// Create auth store
function createAuthStore() {
  const { subscribe, set } = writable<User | null>(null);

  return {
    subscribe,
    initialize: async () => {
      // Check for existing session
      const user = await getCurrentUser();
      set(user);

      // Listen for auth changes
      supabase.auth.onAuthStateChange((_event, session) => {
        set(session?.user ?? null);
      });
    },
    signUp: async (email: string, password: string, name: string) => {
      const { data, error } = await signUp(email, password, name);
      if (error) throw error;
      
      // Save user profile with name
      if (data.user) {
        await supabase.rpc('upsert_user_profile', {
          p_user_id: data.user.id,
          p_display_name: name || email.split('@')[0]
        });
      }
      
      set(data.user);
      return data.user;
    },
    signIn: async (email: string, password: string) => {
      const { data, error } = await signIn(email, password);
      if (error) throw error;
      
      // Ensure user profile exists
      if (data.user) {
        const displayName = data.user.user_metadata?.name || email.split('@')[0];
        await supabase.rpc('upsert_user_profile', {
          p_user_id: data.user.id,
          p_display_name: displayName
        });
      }
      
      set(data.user);
      return data.user;
    },
    signOut: async () => {
      const { error } = await signOut();
      if (error) throw error;
      set(null);
    },
    getUser: () => getCurrentUser()
  };
}

export const authStore = createAuthStore();

// Derived store for user display info
export const userInfo = derived(
  authStore,
  $auth => {
    if (!$auth) return null;
    return {
      email: $auth.email,
      name: $auth.user_metadata?.name || $auth.email?.split('@')[0] || 'User'
    };
  }
);