-- Enable realtime for fellowship_requests table
-- This allows instant updates when fellowship requests are sent/accepted/declined

-- Enable realtime on fellowship_requests table (if not already enabled)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'fellowship_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_requests;
    RAISE NOTICE 'Added fellowship_requests to realtime';
  ELSE
    RAISE NOTICE 'fellowship_requests already has realtime enabled';
  END IF;
END $$;

-- Also enable on fellowships table for instant updates (if not already enabled)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'fellowships'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE fellowships;
    RAISE NOTICE 'Added fellowships to realtime';
  ELSE
    RAISE NOTICE 'fellowships already has realtime enabled';
  END IF;
END $$;

-- Verify realtime is enabled
SELECT 
  schemaname,
  tablename 
FROM 
  pg_publication_tables 
WHERE 
  pubname = 'supabase_realtime'
  AND tablename IN ('fellowship_requests', 'fellowships');