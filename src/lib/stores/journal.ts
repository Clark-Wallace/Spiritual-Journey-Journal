import { writable, derived } from 'svelte/store';
import { 
  getJournalEntries, 
  createJournalEntry, 
  deleteJournalEntry as deleteEntry 
} from '../supabase';
import type { JournalEntry } from '../types';

function createJournalStore() {
  const { subscribe, set, update } = writable<JournalEntry[]>([]);
  
  return {
    subscribe,
    loadEntries: async () => {
      const entries = await getJournalEntries();
      set(entries as JournalEntry[]);
    },
    addEntry: async (entry: Omit<JournalEntry, 'id' | 'createdAt'>) => {
      const newEntry = await createJournalEntry({
        content: entry.content,
        mood: entry.mood,
        gratitude: entry.gratitude,
        date: new Date(entry.date)
      });
      
      if (newEntry) {
        update(entries => [newEntry as JournalEntry, ...entries]);
      }
      return newEntry;
    },
    deleteEntry: async (id: string) => {
      await deleteEntry(id);
      update(entries => entries.filter(e => e.id !== id));
    }
  };
}

// Streak calculation
function createStreakStore() {
  const { subscribe } = derived(
    journalEntries,
    $entries => {
      if ($entries.length === 0) {
        return { current: 0, longest: 0, lastEntry: null, weeklyEntries: 0 };
      }

      // Sort entries by date
      const sorted = [...$entries].sort((a, b) => 
        new Date(b.date).getTime() - new Date(a.date).getTime()
      );

      // Calculate current streak
      let current = 0;
      let lastDate = new Date(sorted[0].date);
      const today = new Date();
      const daysSince = Math.floor((today.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24));
      
      if (daysSince <= 1) {
        current = 1;
        for (let i = 1; i < sorted.length; i++) {
          const prevDate = new Date(sorted[i - 1].date);
          const currDate = new Date(sorted[i].date);
          const daysBetween = Math.floor((prevDate.getTime() - currDate.getTime()) / (1000 * 60 * 60 * 24));
          if (daysBetween <= 1) {
            current++;
          } else {
            break;
          }
        }
      }

      // Calculate weekly entries
      const weekAgo = new Date();
      weekAgo.setDate(weekAgo.getDate() - 7);
      const weeklyEntries = sorted.filter(e => new Date(e.date) >= weekAgo).length;

      return {
        current,
        longest: Math.max(current, 0),
        lastEntry: lastDate,
        weeklyEntries
      };
    }
  );

  return { subscribe };
}

export const journalEntries = createJournalStore();
export const streak = createStreakStore();