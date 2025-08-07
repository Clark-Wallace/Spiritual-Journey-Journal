-- Enable Realtime for all social features
-- This allows real-time updates in the app

-- Enable realtime for chat messages
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;

-- Enable realtime for user presence
ALTER PUBLICATION supabase_realtime ADD TABLE user_presence;

-- Enable realtime for community posts
ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;

-- Enable realtime for reactions
ALTER PUBLICATION supabase_realtime ADD TABLE reactions;

-- Enable realtime for encouragements
ALTER PUBLICATION supabase_realtime ADD TABLE encouragements;

-- Enable realtime for prayer wall
ALTER PUBLICATION supabase_realtime ADD TABLE prayer_wall;

-- Enable realtime for prayer warriors
ALTER PUBLICATION supabase_realtime ADD TABLE prayer_warriors;