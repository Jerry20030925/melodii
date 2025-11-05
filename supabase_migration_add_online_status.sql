-- Migration: Add online status fields to users table
-- Description: Adds is_online boolean and last_seen_at timestamp fields
-- Date: 2025-11-05

-- Add is_online column (default false)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT false;

-- Add last_seen_at column
ALTER TABLE users
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

-- Create index on is_online for faster queries
CREATE INDEX IF NOT EXISTS idx_users_is_online ON users(is_online);

-- Create index on last_seen_at for faster queries
CREATE INDEX IF NOT EXISTS idx_users_last_seen_at ON users(last_seen_at);

-- Add comment to columns
COMMENT ON COLUMN users.is_online IS 'Whether the user is currently online';
COMMENT ON COLUMN users.last_seen_at IS 'Last time the user was seen online';

-- Create a function to automatically update last_seen_at when is_online is set to false
CREATE OR REPLACE FUNCTION update_last_seen_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_online = false AND OLD.is_online = true THEN
        NEW.last_seen_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to call the function
DROP TRIGGER IF EXISTS trigger_update_last_seen_at ON users;
CREATE TRIGGER trigger_update_last_seen_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_last_seen_at();
