import { writable, derived } from 'svelte/store';
import type { JournalEntry, Prayer } from './types';
import { 
  getJournalEntries, 
  createJournalEntry, 
  deleteJournalEntry,
  getPrayers,
  createPrayer,
  answerPrayer as answerPrayerApi,
  deletePrayer
} from './supabase';

// Journal entries store (Supabase)
function createJournalStore() {
  const { subscribe, set, update } = writable<JournalEntry[]>([]);

  return {
    subscribe,
    loadEntries: async () => {
      const entries = await getJournalEntries();
      set(entries as JournalEntry[]);
    },
    addEntry: async (entry: Omit<JournalEntry, 'id' | 'createdAt'>) => {
      try {
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
      } catch (error) {
        console.error('Error adding entry:', error);
        throw error;
      }
    },
    deleteEntry: async (id: string) => {
      try {
        await deleteJournalEntry(id);
        update(entries => entries.filter(e => e.id !== id));
      } catch (error) {
        console.error('Error deleting entry:', error);
        throw error;
      }
    }
  };
}

// Prayers store (Supabase)
function createPrayerStore() {
  const { subscribe, set, update } = writable<Prayer[]>([]);

  return {
    subscribe,
    loadPrayers: async () => {
      const prayers = await getPrayers();
      set(prayers as Prayer[]);
    },
    addPrayer: async (prayer: Omit<Prayer, 'id' | 'createdAt'>) => {
      try {
        const newPrayer = await createPrayer({
          request: prayer.request,
          category: prayer.category
        });
        
        if (newPrayer) {
          update(prayers => [newPrayer as Prayer, ...prayers]);
        }
        return newPrayer;
      } catch (error) {
        console.error('Error adding prayer:', error);
        throw error;
      }
    },
    answerPrayer: async (id: string, note: string) => {
      try {
        const updated = await answerPrayerApi(id, note);
        if (updated) {
          update(prayers => 
            prayers.map(p => p.id === id ? updated as Prayer : p)
          );
        }
        return updated;
      } catch (error) {
        console.error('Error answering prayer:', error);
        throw error;
      }
    },
    deletePrayer: async (id: string) => {
      try {
        await deletePrayer(id);
        update(prayers => prayers.filter(p => p.id !== id));
      } catch (error) {
        console.error('Error deleting prayer:', error);
        throw error;
      }
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

      // For simplicity, longest = current for now
      return {
        current,
        longest: Math.max(current, 0), // TODO: Store longest streak in database
        lastEntry: lastDate,
        weeklyEntries
      };
    }
  );

  return { subscribe };
}

export const journalEntries = createJournalStore();
export const prayers = createPrayerStore();
export const streak = createStreakStore();
export const currentView = writable<'home' | 'journal' | 'guidance' | 'community' | 'theway'>('home');