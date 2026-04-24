import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { getDailyRewardState, claimDailyReward } from '../src/services/dailyRewardService.js';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const TEST_USER_ID = 'test-user-123';

async function ensureRecord() {
  let existing = await prisma.dailyReward.findUnique({
    where: { userId: TEST_USER_ID }
  });
  if (!existing) {
    await prisma.user.create({
      data: { id: TEST_USER_ID, createdAt: new Date() }
    });
    await prisma.dailyReward.create({
      data: {
        userId: TEST_USER_ID,
        currentDay: 1,
        totalCoins: 0,
        cycleStartedAt: new Date()
      }
    });
  }
}

describe('Daily Reward Service - State', () => {
  beforeEach(async () => {
    await prisma.dailyReward.deleteMany();
    await ensureRecord();
  });

  it('should return state for existing record', async () => {
    const result = await getDailyRewardState(TEST_USER_ID);
    expect(result).not.toBeNull();
    expect(result!.current_day).toBe(1);
    expect(result!.total_coins).toBe(0);
    expect(result!.can_claim).toBe(true);
    expect(result!.cooldown_until).toBeNull();
    expect(result!.coins_to_win).toBe(100);
  });

  it('should return initial state when no record exists', async () => {
    await prisma.dailyReward.deleteMany();
    const result = await getDailyRewardState(TEST_USER_ID);
    expect(result!.current_day).toBe(1);
    expect(result!.total_coins).toBe(0);
    expect(result!.can_claim).toBe(true);
  });

  it('should return cooldown state when recently claimed', async () => {
    await prisma.dailyReward.updateMany({
      where: { userId: TEST_USER_ID },
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 2 * 60 * 1000), // 2 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState(TEST_USER_ID);
    
    expect(state!.can_claim).toBe(false);
    expect(state!.cooldown_until).not.toBeNull();
    expect(state!.current_day).toBe(1);
  });

  it('should allow claim after cooldown (5+ minutes)', async () => {
    await prisma.dailyReward.updateMany({
      where: { userId: TEST_USER_ID },
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 6 * 60 * 1000), // 6 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState(TEST_USER_ID);
    
    expect(state!.can_claim).toBe(true);
    expect(state!.cooldown_until).toBeNull();
  });

  it('should indicate reset needed when gap > 10 minutes', async () => {
    await prisma.dailyReward.updateMany({
      where: { userId: TEST_USER_ID },
      data: {
        currentDay: 3,
        lastClaimedAt: new Date(Date.now() - 15 * 60 * 1000), // 15 minutes ago
        totalCoins: 600
      }
    });

    const state = await getDailyRewardState(TEST_USER_ID);
    
    expect(state!.can_claim).toBe(true);
    expect(state!.reset_needed).toBe(true);
  });
});

describe('Daily Reward Service - Claim', () => {
  beforeEach(async () => {
    vi.useFakeTimers();
  });

  afterEach(async () => {
    await prisma.dailyReward.deleteMany();
    vi.useRealTimers();
  });

  it('should award first reward (100 coins, day 1)', async () => {
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);
    expect(result.total_coins).toBe(100);
    expect(result.reset_occurred).toBe(false);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(dbReward!.currentDay).toBe(1);
    expect(dbReward!.totalCoins).toBe(100);
  });

  it('should reject claim during cooldown', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    await expect(claimDailyReward(TEST_USER_ID))
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should advance day after cooldown (day 1 -> day 2)', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.coins_awarded).toBe(200);
    expect(result.current_day).toBe(2);
    expect(result.total_coins).toBe(300);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(dbReward!.currentDay).toBe(2);
  });

  it('should reset series when gap > 10 minutes', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 15, 0));
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.reset_occurred).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);
    
    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(dbReward!.currentDay).toBe(1);
  });

  it('should cycle from day 7 back to day 1', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID); // Day 1
    
    const times = [6, 12, 18, 24, 30];
    for (let i = 0; i < times.length; i++) {
      vi.setSystemTime(new Date(2024, 0, 1, 0, times[i], 0));
      await claimDailyReward(TEST_USER_ID); // Claims days 2-6
    }
    
    const beforeClaim = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(beforeClaim!.currentDay).toBe(6);
    expect(beforeClaim!.totalCoins).toBe(2100);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 36, 0));
    let result = await claimDailyReward(TEST_USER_ID);
    expect(result.coins_awarded).toBe(1000); // Day 7 reward (special bonus)
    expect(result.current_day).toBe(7);

    const afterDay7 = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 42, 0));
    result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.coins_awarded).toBe(100); // Day 1 reward (cycled)
    expect(result.current_day).toBe(1);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(dbReward!.totalCoins).toBe(3200); // Full cycle + restart
  });

  it('should accumulate coins correctly over multiple claims', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    let result = await claimDailyReward(TEST_USER_ID);
    expect(result.total_coins).toBe(100);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    result = await claimDailyReward(TEST_USER_ID);
    expect(result.total_coins).toBe(300);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 12, 0));
    result = await claimDailyReward(TEST_USER_ID);
    expect(result.total_coins).toBe(600);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 18, 0));
    result = await claimDailyReward(TEST_USER_ID);
    expect(result.total_coins).toBe(1000);
  });

  it('should not allow double claims within cooldown', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    await expect(claimDailyReward(TEST_USER_ID))
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should handle exactly at cooldown boundary', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 5, 0));
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(200);
  });

  it('should handle reset threshold behavior', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 10, 1));
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.reset_occurred).toBe(true);
  });

  it('should create user and daily reward when none exists', async () => {
    await prisma.dailyReward.deleteMany();
    await prisma.user.deleteMany();
    
    const result = await claimDailyReward(TEST_USER_ID);
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);

    const user = await prisma.user.findUnique({
      where: { id: TEST_USER_ID }
    });
    expect(user).not.toBeNull();

    const reward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    expect(reward).not.toBeNull();
    expect(reward!.userId).toBe(TEST_USER_ID);
  });

  it('should track separate state for different users', async () => {
    const USER_2 = 'test-user-456';
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(TEST_USER_ID); // User 1 claims day 1
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    const result = await claimDailyReward(USER_2); // User 2 claims day 1 (separate)
    
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);

    const user1Reward = await prisma.dailyReward.findUnique({
      where: { userId: TEST_USER_ID }
    });
    const user2Reward = await prisma.dailyReward.findUnique({
      where: { userId: USER_2 }
    });
    
    expect(user1Reward!.totalCoins).toBe(100);
    expect(user2Reward!.totalCoins).toBe(100);
  });
});
