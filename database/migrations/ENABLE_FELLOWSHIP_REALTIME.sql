-- Enable realtime for fellowship_requests table
-- This allows instant updates when fellowship requests are sent/accepted/declined

-- Enable realtime on fellowship_requests table
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_requests;

-- Also enable on fellowships table for instant updates
ALTER PUBLICATION supabase_realtime ADD TABLE fellowships;

-- Verify realtime is enabled
SELECT 
  schemaname,
  tablename 
FROM 
  pg_publication_tables 
WHERE 
  pubname = 'supabase_realtime'
  AND tablename IN ('fellowship_requests', 'fellowships');