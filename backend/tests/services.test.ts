import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createGuest, verifyToken } from '../src/services/authService.js';
import { getDailyRewardState, claimDailyReward } from '../src/services/dailyRewardService.js';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

describe('Auth Service', () => {
  beforeEach(async () => {
    await prisma.dailyReward.deleteMany();
    await prisma.user.deleteMany();
  });

  it('should create a guest user with token and daily reward record', async () => {
    const result = await createGuest();
    
    expect(result).toHaveProperty('user_id');
    expect(result).toHaveProperty('token');
    expect(typeof result.user_id).toBe('string');
    expect(typeof result.token).toBe('string');
  });

  it('should verify a valid token', async () => {
    const guest = await createGuest();
    const authResult = await verifyToken(`Bearer ${guest.token}`);
    
    expect(authResult).toHaveProperty('userId');
    expect(authResult).toHaveProperty('dailyReward');
    expect(authResult.userId).toBe(guest.user_id);
  });

  it('should reject invalid token', async () => {
    await expect(verifyToken('Bearer invalid-token'))
      .rejects.toThrow();
  });

  it('should reject missing authorization header', async () => {
    await expect(verifyToken(null))
      .rejects.toThrow('Invalid or missing authorization header');
  });
});

describe('Daily Reward Service - State', () => {
  beforeEach(async () => {
    await prisma.dailyReward.deleteMany();
    await prisma.user.deleteMany();
  });

  it('should return null for non-existent user', async () => {
    const result = await getDailyRewardState('non-existent');
    expect(result).toBeNull();
  });

  it('should return initial state for new user (first claim)', async () => {
    await createGuest();
    
    const users = await prisma.user.findMany({ include: { dailyReward: true } });
    const userId = users[0].id;
    
    const state = await getDailyRewardState(userId);
    
    expect(state).not.toBeNull();
    expect(state!.current_day).toBe(1);
    expect(state!.total_coins).toBe(0);
    expect(state!.can_claim).toBe(true);
    expect(state!.cooldown_until).toBeNull();
    expect(state!.coins_to_win).toBe(100);
  });

  it('should return cooldown state when recently claimed', async () => {
    const user = await createGuest();
    
    await prisma.dailyReward.update({
      where: { userId: user.user_id },
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 2 * 60 * 1000), // 2 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState(user.user_id);
    
    expect(state!.can_claim).toBe(false);
    expect(state!.cooldown_until).not.toBeNull();
    expect(state!.current_day).toBe(1);
  });

  it('should allow claim after cooldown (5+ minutes)', async () => {
    const user = await createGuest();
    
    await prisma.dailyReward.update({
      where: { userId: user.user_id },
      data: {
        currentDay: 1,
        lastClaimedAt: new Date(Date.now() - 6 * 60 * 1000), // 6 minutes ago
        totalCoins: 100
      }
    });

    const state = await getDailyRewardState(user.user_id);
    
    expect(state!.can_claim).toBe(true);
    expect(state!.cooldown_until).toBeNull();
  });

  it('should indicate reset needed when gap > 10 minutes', async () => {
    const user = await createGuest();
    
    await prisma.dailyReward.update({
      where: { userId: user.user_id },
      data: {
        currentDay: 3,
        lastClaimedAt: new Date(Date.now() - 15 * 60 * 1000), // 15 minutes ago
        totalCoins: 600
      }
    });

    const state = await getDailyRewardState(user.user_id);
    
    expect(state!.can_claim).toBe(true);
    expect(state!.reset_needed).toBe(true);
  });
});

describe('Daily Reward Service - Claim', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(async () => {
    await prisma.dailyReward.deleteMany();
    await prisma.user.deleteMany();
    vi.useRealTimers();
  });

  it('should award first reward (100 coins, day 1)', async () => {
    const user = await createGuest();
    
    const result = await claimDailyReward(user.user_id);
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(100);
    expect(result.current_day).toBe(1); // Claimed day 1's reward
    expect(result.total_coins).toBe(100);
    expect(result.reset_occurred).toBe(false);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    expect(dbReward!.currentDay).toBe(1);
    expect(dbReward!.totalCoins).toBe(100);
  });

  it('should reject claim during cooldown', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    // Try to claim immediately (should fail - still in cooldown)
    await expect(claimDailyReward(user.user_id))
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should advance day after cooldown (day 1 -> day 2)', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    // Second claim after cooldown (6 minutes later)
    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    const result = await claimDailyReward(user.user_id);
    
    expect(result.coins_awarded).toBe(200); // Day 2 reward
    expect(result.current_day).toBe(2); // Claimed day 2's reward
    expect(result.total_coins).toBe(300);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    expect(dbReward!.currentDay).toBe(2);
  });

  it('should reset series when gap > 10 minutes', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    // Second claim after >10 min gap (resets series)
    vi.setSystemTime(new Date(2024, 0, 1, 0, 15, 0));
    const result = await claimDailyReward(user.user_id);
    
    expect(result.reset_occurred).toBe(true);
    expect(result.coins_awarded).toBe(100); // Back to day 1 reward
    expect(result.current_day).toBe(1); // Reset to day 1
    
    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    expect(dbReward!.currentDay).toBe(1);
  });

  it('should cycle from day 7 back to day 1', async () => {
    const user = await createGuest();
    
    // Claim days sequentially, each time 6 minutes after previous (within cooldown window)
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id); // Day 1
    
    const times = [6, 12, 18, 24, 30]; // minutes: claims at day 2-6
    for (let i = 0; i < times.length; i++) {
      vi.setSystemTime(new Date(2024, 0, 1, 0, times[i], 0));
      await claimDailyReward(user.user_id); // Claims days 2-6
    }
    
    const beforeClaim = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    expect(beforeClaim!.currentDay).toBe(6);
    expect(beforeClaim!.totalCoins).toBe(2100); // 100+200+300+400+500+600
    
    // Claim day 7 reward (at t=36 min)
    vi.setSystemTime(new Date(2024, 0, 1, 0, 36, 0));
    let result = await claimDailyReward(user.user_id);
    expect(result.coins_awarded).toBe(700); // Day 7 reward (REWARD_SCHEDULE[6]=700)
    expect(result.current_day).toBe(7);

    const afterDay7 = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    
    // Cycle to day 1 - claim at t=42 min (6 min after day 6)
    vi.setSystemTime(new Date(2024, 0, 1, 0, 42, 0));
    result = await claimDailyReward(user.user_id);
    
    expect(result.coins_awarded).toBe(100); // Day 1 reward (cycled)
    expect(result.current_day).toBe(1);

    const dbReward = await prisma.dailyReward.findUnique({
      where: { userId: user.user_id }
    });
    expect(dbReward!.totalCoins).toBe(2900); // 2800 + 100
  });

  it('should accumulate coins correctly over multiple claims', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    let result = await claimDailyReward(user.user_id);
    expect(result.total_coins).toBe(100);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 6, 0));
    result = await claimDailyReward(user.user_id);
    expect(result.total_coins).toBe(300);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 12, 0));
    result = await claimDailyReward(user.user_id);
    expect(result.total_coins).toBe(600);

    vi.setSystemTime(new Date(2024, 0, 1, 0, 18, 0));
    result = await claimDailyReward(user.user_id);
    expect(result.total_coins).toBe(1000);
  });

  it('should not allow double claims within cooldown', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    await expect(claimDailyReward(user.user_id))
      .rejects.toThrow('COOLDOWN_ACTIVE');
  });

  it('should handle exactly at cooldown boundary', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 5, 0));
    const result = await claimDailyReward(user.user_id);
    
    expect(result.success).toBe(true);
    expect(result.coins_awarded).toBe(200);
  });

  it('should handle reset threshold behavior', async () => {
    const user = await createGuest();
    
    vi.setSystemTime(new Date(2024, 0, 1, 0, 0, 0));
    await claimDailyReward(user.user_id);
    
    // More than 10 minutes - should reset
    vi.setSystemTime(new Date(2024, 0, 1, 0, 10, 1));
    const result = await claimDailyReward(user.user_id);
    
    expect(result.reset_occurred).toBe(true);
  });
});
