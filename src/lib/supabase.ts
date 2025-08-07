import { createClient } from '@supabase/supabase-js';
import type { Database } from './database.types';

// These will be replaced with your actual Supabase project details
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'your-anon-key';

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY);

// Auth helpers
export const signUp = async (email: string, password: string, name: string) => {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        name: name
      }
    }
  });
  return { data, error };
};

export const signIn = async (email: string, password: string) => {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });
  return { data, error };
};

export const signOut = async () => {
  const { error } = await supabase.auth.signOut();
  return { error };
};

export const getCurrentUser = async () => {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
};

// Database helpers
export const getJournalEntries = async () => {
  const user = await getCurrentUser();
  if (!user) return [];
  
  const { data, error } = await supabase
    .from('journal_entries')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });
  
  if (error) {
    console.error('Error fetching entries:', error);
    return [];
  }
  
  // Map database fields to app fields
  return (data || []).map(entry => ({
    ...entry,
    date: entry.entry_date, // Map entry_date to date
    createdAt: entry.created_at
  }));
};

export const createJournalEntry = async (entry: {
  content: string;
  mood: string;
  gratitude: string[];
  date: Date;
}) => {
  const user = await getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  const { data, error } = await supabase
    .from('journal_entries')
    .insert({
      user_id: user.id,
      content: entry.content,
      mood: entry.mood,
      gratitude: entry.gratitude,
      entry_date: entry.date.toISOString()
    })
    .select()
    .single();
  
  if (error) throw error;
  
  // Map database fields to app fields
  return {
    ...data,
    date: data.entry_date,
    createdAt: data.created_at
  };
};

export const deleteJournalEntry = async (id: string) => {
  const { error } = await supabase
    .from('journal_entries')
    .delete()
    .eq('id', id);
  
  if (error) throw error;
};

export const getPrayers = async () => {
  const user = await getCurrentUser();
  if (!user) return [];
  
  const { data, error } = await supabase
    .from('prayers')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });
  
  if (error) {
    console.error('Error fetching prayers:', error);
    return [];
  }
  
  // Map database fields to app fields
  return (data || []).map(prayer => ({
    ...prayer,
    createdAt: prayer.created_at,
    answeredDate: prayer.answered_date,
    answeredNote: prayer.answered_note
  }));
};

export const createPrayer = async (prayer: {
  request: string;
  category: string;
}) => {
  const user = await getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  const { data, error } = await supabase
    .from('prayers')
    .insert({
      user_id: user.id,
      request: prayer.request,
      category: prayer.category,
      status: 'active'
    })
    .select()
    .single();
  
  if (error) throw error;
  
  // Map database fields to app fields
  return {
    ...data,
    createdAt: data.created_at,
    answeredDate: data.answered_date,
    answeredNote: data.answered_note
  };
};

export const answerPrayer = async (id: string, note: string) => {
  const { data, error } = await supabase
    .from('prayers')
    .update({
      status: 'answered',
      answered_note: note,
      answered_date: new Date().toISOString()
    })
    .eq('id', id)
    .select()
    .single();
  
  if (error) throw error;
  return data;
};

export const deletePrayer = async (id: string) => {
  const { error } = await supabase
    .from('prayers')
    .delete()
    .eq('id', id);
  
  if (error) throw error;
};

// Community sharing functions
export const shareToCommunity = async (post: {
  mood?: string;
  gratitude: string[];
  content?: string;
  prayer?: string;
  shareType: 'post' | 'prayer' | 'testimony' | 'praise';
  isAnonymous: boolean;
  journalEntryId?: string; // Link to original journal entry
}) => {
  const user = await getCurrentUser();
  if (!user) throw new Error('User not authenticated');
  
  const { data, error } = await supabase
    .from('community_posts')
    .insert({
      user_id: user.id,
      user_name: post.isAnonymous ? null : user.user_metadata?.name || user.email?.split('@')[0],
      content: post.content,
      mood: post.mood,
      gratitude: post.gratitude,
      prayer: post.prayer,
      is_anonymous: post.isAnonymous,
      share_type: post.shareType
      // Removed journal_entry_id and source_type until database is updated
    })
    .select()
    .single();
  
  if (error) throw error;
  
  // If it's a prayer request, also add to prayer wall
  if (post.shareType === 'prayer' && post.prayer) {
    await supabase
      .from('prayer_wall')
      .insert({
        post_id: data.id,
        user_id: user.id,
        prayer_request: post.prayer,
        anonymous: post.isAnonymous
      });
  }
  
  return data;
};