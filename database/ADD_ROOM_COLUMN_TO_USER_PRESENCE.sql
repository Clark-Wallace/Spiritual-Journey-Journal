-- Add current_room column to user_presence table for multi-room chat support
ALTER TABLE user_presence ADD COLUMN IF NOT EXISTS current_room VARCHAR(50) DEFAULT 'fellowship';

-- Update any existing records to have the default room
UPDATE user_presence SET current_room = 'fellowship' WHERE current_room IS NULL;

-- Create index for better performance when querying by room
CREATE INDEX IF NOT EXISTS idx_user_presence_current_room ON user_presence(current_room);

-- Create compound index for user_id + current_room queries
CREATE INDEX IF NOT EXISTS idx_user_presence_user_current_room ON user_presence(user_id, current_room);