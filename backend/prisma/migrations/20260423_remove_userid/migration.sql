-- Remove userId column from DailyReward table (if it exists)
ALTER TABLE "DailyReward" DROP CONSTRAINT IF EXISTS "DailyReward_userId_fkey";
DROP INDEX IF EXISTS "DailyReward_userId_key";
ALTER TABLE "DailyReward" DROP COLUMN IF EXISTS "userId";

-- Drop User table if it still exists (from old schema)
DROP TABLE IF EXISTS "User" CASCADE;
