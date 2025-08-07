-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Journal entries table
CREATE TABLE IF NOT EXISTS journal_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  mood VARCHAR(50),
  gratitude TEXT[] DEFAULT '{}',
  entry_date TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Prayers table
CREATE TABLE IF NOT EXISTS prayers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  request TEXT NOT NULL,
  category VARCHAR(100),
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'answered')),
  answered_note TEXT,
  answered_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Bible verses table (for future vector search)
CREATE TABLE IF NOT EXISTS bible_verses (
  id VARCHAR(20) PRIMARY KEY, -- Format: "GEN.1.1"
  book VARCHAR(50) NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  text TEXT NOT NULL,
  testament VARCHAR(3) CHECK (testament IN ('old', 'new')),
  embedding vector(1536) -- For OpenAI embeddings
);

-- Create indexes for better performance
CREATE INDEX idx_journal_entries_user_id ON journal_entries(user_id);
CREATE INDEX idx_journal_entries_entry_date ON journal_entries(entry_date DESC);
CREATE INDEX idx_prayers_user_id ON prayers(user_id);
CREATE INDEX idx_prayers_status ON prayers(status);
CREATE INDEX idx_bible_verses_book ON bible_verses(book);

-- Enable Row Level Security (RLS)
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;

-- RLS Policies for journal_entries
CREATE POLICY "Users can view own journal entries" ON journal_entries
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own journal entries" ON journal_entries
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own journal entries" ON journal_entries
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own journal entries" ON journal_entries
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for prayers
CREATE POLICY "Users can view own prayers" ON prayers
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own prayers" ON prayers
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own prayers" ON prayers
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own prayers" ON prayers
  FOR DELETE USING (auth.uid() = user_id);

-- Function for vector similarity search (for future Bible RAG)
CREATE OR REPLACE FUNCTION search_bible(
  query_embedding vector(1536),
  match_count INT DEFAULT 5,
  match_threshold FLOAT DEFAULT 0.7
)
RETURNS TABLE (
  id VARCHAR,
  book VARCHAR,
  chapter INTEGER,
  verse INTEGER,
  text TEXT,
  similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    bv.id,
    bv.book,
    bv.chapter,
    bv.verse,
    bv.text,
    1 - (bv.embedding <=> query_embedding) AS similarity
  FROM bible_verses bv
  WHERE 1 - (bv.embedding <=> query_embedding) > match_threshold
  ORDER BY bv.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- Updated at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_journal_entries_updated_at
  BEFORE UPDATE ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_prayers_updated_at
  BEFORE UPDATE ON prayers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();