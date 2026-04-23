import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { getDailyRewardState, claimDailyReward } from '../src/services/dailyRewardService.js';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function ensureRecord() {
  let existing = await prisma.dailyReward.findFirst();
  if (!existing) {
    await prisma.dailyReward.create({ data: { currentDay: 1, totalCoins: 0 } });
  }
}

describe('Daily Reward Service - State', () => {
  beforeEach(async () => {
    await prisma.dailyReward.deleteMany();
    await ensureRecord();
  });

  it('should return state for existing record', async () => {
    const result = await getDailyRewardState();
    expect(result).not.toBeNull();
    expect(result!.current_day).toBe(1);
    expect(result!.total_coins).toBe(0);
    expect(result!.can_claim).toBe(true);
    expect(result!.cooldown_until).toBeNull();
    expect(result!.coins_to_win).toBe(100);
  });

  it('should return initial state when no record exists', async () => {
    await prisma.dailyReward.deleteMany();
    const result = await getDailyRewardState();
    expect(result!.current_day).toBe(1);
    expect(result!.total_coins).toBe(0);
    expect(result!.can_claim).toBe(true);
  });

  it('should return cooldown state when recently claimed', async () => {
    await prisma.dailyReward.updateMany({
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 2 * 60 * 1000), // 2 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState();
    
    expect(state!.can_claim).toBe(false);
    expect(state!.cooldown_until).not.toBeNull();
    expect(state!.current_day).toBe(1);
  });

  it('should allow claim after cooldown (5+ minutes)', async () => {
    await prisma.dailyReward.updateMany({
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 6 * 60 * 1000), // 6 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState();
    
    expect(state!.can_claim).toBe(true);
    expect(state!.cooldown_until).toBeNull();
  });

  it('should indicate reset needed when gap > 10 minutes', async () => {
    await prisma.dailyReward.updateMany({
      data: {
        currentDay: 3,
        lastClaimedAt: new Date(Date.now() - 15 * 60 * 1000), // 15 minutes ago
        totalCoins: 600
      }
    });

    const state = await getDailyRewardState();
    
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
    const result = await claimDailyReward();
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);
    expect(result.total_coins).toBe(100);
    expect(result.reset_occurred).toBe(false);

    const dbReward = await prisma.dailyReward.findFirst();
    expect(dbReward!.currentDay).toBe(1);
    expect(dbReward!.totalCoins).toBe(100);
  });

  it('should reject claim during cooldown', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    await expect(claimDailyReward())
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should advance day after cooldown (day 1 -> day 2)', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    const result = await claimDailyReward();
    
    expect(result.coins_awarded).toBe(200);
    expect(result.current_day).toBe(2);
    expect(result.total_coins).toBe(300);

    const dbReward = await prisma.dailyReward.findFirst();
    expect(dbReward!.currentDay).toBe(2);
  });

  it('should reset series when gap > 10 minutes', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 15, 0));
    const result = await claimDailyReward();
    
    expect(result.reset_occurred).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1);
    
    const dbReward = await prisma.dailyReward.findFirst();
    expect(dbReward!.currentDay).toBe(1);
  });

  it('should cycle from day 7 back to day 1', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(); // Day 1
    
    const times = [6, 12, 18, 24, 30];
    for (let i = 0; i < times.length; i++) {
      vi.setSystemTime(new Date(2024, 0, 1, 0, times[i], 0));
      await claimDailyReward(); // Claims days 2-6
    }
    
    const beforeClaim = await prisma.dailyReward.findFirst();
    expect(beforeClaim!.currentDay).toBe(6);
    expect(beforeClaim!.totalCoins).toBe(2100);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 36, 0));
    let result = await claimDailyReward();
    expect(result.coins_awarded).toBe(1000); // Day 7 reward (special bonus)
    expect(result.current_day).toBe(7);

    const afterDay7 = await prisma.dailyReward.findFirst();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 42, 0));
    result = await claimDailyReward();
    
    expect(result.coins_awarded).toBe(100); // Day 1 reward (cycled)
    expect(result.current_day).toBe(1);

    const dbReward = await prisma.dailyReward.findFirst();
    expect(dbReward!.totalCoins).toBe(3200); // Full cycle + restart
  });

  it('should accumulate coins correctly over multiple claims', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    let result = await claimDailyReward();
    expect(result.total_coins).toBe(100);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    result = await claimDailyReward();
    expect(result.total_coins).toBe(300);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 12, 0));
    result = await claimDailyReward();
    expect(result.total_coins).toBe(600);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 18, 0));
    result = await claimDailyReward();
    expect(result.total_coins).toBe(1000);
  });

  it('should not allow double claims within cooldown', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    await expect(claimDailyReward())
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should handle exactly at cooldown boundary', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 5, 0));
    const result = await claimDailyReward();
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(200);
  });

  it('should handle reset threshold behavior', async () => {
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 10, 1));
    const result = await claimDailyReward();
    
    expect(result.reset_occurred).toBe(true);
  });
});
