-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DailyReward" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "currentDay" INTEGER NOT NULL DEFAULT 1,
    "lastClaimedAt" TIMESTAMP(3),
    "totalCoins" INTEGER NOT NULL DEFAULT 0,
    "cycleStartedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DailyReward_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_tokenHash_key" ON "User"("tokenHash");

-- CreateIndex
CREATE UNIQUE INDEX "DailyReward_userId_key" ON "DailyReward"("userId");

-- AddForeignKey
ALTER TABLE "DailyReward" ADD CONSTRAINT "DailyReward_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
