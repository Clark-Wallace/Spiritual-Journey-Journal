export type Database = {
  public: {
    Tables: {
      journal_entries: {
        Row: {
          id: string;
          user_id: string;
          content: string;
          mood: string;
          gratitude: string[];
          entry_date: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          content: string;
          mood: string;
          gratitude: string[];
          entry_date: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          content?: string;
          mood?: string;
          gratitude?: string[];
          entry_date?: string;
          created_at?: string;
          updated_at?: string;
        };
      };
      prayers: {
        Row: {
          id: string;
          user_id: string;
          request: string;
          category: string;
          status: 'active' | 'answered';
          answered_note: string | null;
          answered_date: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          request: string;
          category: string;
          status?: 'active' | 'answered';
          answered_note?: string | null;
          answered_date?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          request?: string;
          category?: string;
          status?: 'active' | 'answered';
          answered_note?: string | null;
          answered_date?: string | null;
          created_at?: string;
          updated_at?: string;
        };
      };
      bible_verses: {
        Row: {
          id: string;
          book: string;
          chapter: number;
          verse: number;
          text: string;
          testament: 'old' | 'new';
          embedding: number[] | null;
        };
        Insert: {
          id: string;
          book: string;
          chapter: number;
          verse: number;
          text: string;
          testament: 'old' | 'new';
          embedding?: number[] | null;
        };
        Update: {
          id?: string;
          book?: string;
          chapter?: number;
          verse?: number;
          text?: string;
          testament?: 'old' | 'new';
          embedding?: number[] | null;
        };
      };
    };
    Views: {};
    Functions: {
      search_bible: {
        Args: {
          query_embedding: number[];
          match_count: number;
          match_threshold: number;
        };
        Returns: {
          id: string;
          book: string;
          chapter: number;
          verse: number;
          text: string;
          similarity: number;
        }[];
      };
    };
    Enums: {};
  };
};