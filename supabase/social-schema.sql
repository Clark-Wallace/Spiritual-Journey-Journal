-- Community Posts (public journal entries)
CREATE TABLE IF NOT EXISTS community_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_name VARCHAR(255),
  content TEXT,
  mood VARCHAR(50),
  gratitude TEXT[],
  prayer TEXT,
  is_anonymous BOOLEAN DEFAULT false,
  share_type VARCHAR(20) DEFAULT 'post' CHECK (share_type IN ('post', 'prayer', 'testimony', 'praise')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Prayer Wall specific entries
CREATE TABLE IF NOT EXISTS prayer_wall (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  prayer_request TEXT NOT NULL,
  category VARCHAR(50) DEFAULT 'general',
  is_urgent BOOLEAN DEFAULT false,
  is_answered BOOLEAN DEFAULT false,
  answered_date TIMESTAMPTZ,
  testimony TEXT,
  anonymous BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Prayer Warriors (who's praying for what)
CREATE TABLE IF NOT EXISTS prayer_warriors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  prayer_id UUID REFERENCES prayer_wall(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  committed_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(prayer_id, user_id)
);

-- Encouragements (comments on posts/prayers)
CREATE TABLE IF NOT EXISTS encouragements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  prayer_id UUID REFERENCES prayer_wall(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_name VARCHAR(255),
  message TEXT NOT NULL,
  scripture_reference VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CHECK (
    (post_id IS NOT NULL AND prayer_id IS NULL) OR 
    (post_id IS NULL AND prayer_id IS NOT NULL)
  )
);

-- Reactions (Amen, Praying, Hallelujah, etc.)
CREATE TABLE IF NOT EXISTS reactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  prayer_id UUID REFERENCES prayer_wall(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  reaction_type VARCHAR(20) CHECK (reaction_type IN ('amen', 'praying', 'hallelujah', 'love', 'strength')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(post_id, user_id, reaction_type),
  UNIQUE(prayer_id, user_id, reaction_type),
  CHECK (
    (post_id IS NOT NULL AND prayer_id IS NULL) OR 
    (post_id IS NULL AND prayer_id IS NOT NULL)
  )
);

-- Create indexes
CREATE INDEX idx_community_posts_user_id ON community_posts(user_id);
CREATE INDEX idx_community_posts_created_at ON community_posts(created_at DESC);
CREATE INDEX idx_prayer_wall_category ON prayer_wall(category);
CREATE INDEX idx_prayer_wall_urgent ON prayer_wall(is_urgent);
CREATE INDEX idx_prayer_warriors_user ON prayer_warriors(user_id);

-- Enable RLS
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayer_wall ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayer_warriors ENABLE ROW LEVEL SECURITY;
ALTER TABLE encouragements ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for community_posts
CREATE POLICY "Anyone can view public posts" ON community_posts
  FOR SELECT USING (true);

CREATE POLICY "Users can create own posts" ON community_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own posts" ON community_posts
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own posts" ON community_posts
  FOR DELETE USING (auth.uid() = user_id);

-- RLS for prayer_wall
CREATE POLICY "Anyone can view prayers" ON prayer_wall
  FOR SELECT USING (true);

CREATE POLICY "Users can create prayers" ON prayer_wall
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own prayers" ON prayer_wall
  FOR UPDATE USING (auth.uid() = user_id);

-- RLS for prayer_warriors
CREATE POLICY "Anyone can see who's praying" ON prayer_warriors
  FOR SELECT USING (true);

CREATE POLICY "Users can commit to pray" ON prayer_warriors
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can uncommit from prayer" ON prayer_warriors
  FOR DELETE USING (auth.uid() = user_id);

-- RLS for encouragements
CREATE POLICY "Anyone can view encouragements" ON encouragements
  FOR SELECT USING (true);

CREATE POLICY "Users can create encouragements" ON encouragements
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- RLS for reactions
CREATE POLICY "Anyone can view reactions" ON reactions
  FOR SELECT USING (true);

CREATE POLICY "Users can add reactions" ON reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove own reactions" ON reactions
  FOR DELETE USING (auth.uid() = user_id);