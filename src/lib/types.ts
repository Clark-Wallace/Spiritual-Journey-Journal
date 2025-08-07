export interface JournalEntry {
  id: string;
  date: Date;
  mood?: 'grateful' | 'peaceful' | 'joyful' | 'hopeful' | 'reflective' | 'troubled' | 'anxious' | 'seeking';
  gratitude: string[];
  content?: string;
  prayer?: string;
  createdAt: Date;
}

export interface Prayer {
  id: string;
  request: string; // This is what's stored in database
  category: 'thanksgiving' | 'intercession' | 'petition' | 'confession' | 'praise' | 'guidance';
  status: 'active' | 'answered'; // Database uses 'active' not 'ongoing'
  answeredNote?: string;
  answeredDate?: Date;
  createdAt: Date;
}

export interface Streak {
  current: number;
  longest: number;
  lastEntry: Date | null;
  weeklyEntries: number;
}