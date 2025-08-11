-- Enable realtime for community_posts table

-- Check if community_posts is already in the publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'community_posts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
    RAISE NOTICE 'Added community_posts to realtime publication';
  ELSE
    RAISE NOTICE 'community_posts already in realtime publication';
  END IF;
END $$;

-- Also ensure reactions and encouragements are in realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'reactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE reactions;
    RAISE NOTICE 'Added reactions to realtime publication';
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'encouragements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE encouragements;
    RAISE NOTICE 'Added encouragements to realtime publication';
  END IF;
END $$;

-- List all tables in realtime
SELECT 'Tables enabled for realtime:' as status;
SELECT tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

SELECT 'Realtime enabled for posts!' as status;