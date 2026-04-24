import { PrismaClient } from '@prisma/client';
import type { DailyRewardState, ClaimResult, CooldownError } from '../types/index.js';
import { REWARD_SCHEDULE, COOLDOWN_MS, RESET_THRESHOLD_MS, MAX_DAY } from '../utils/constants.js';

const prisma = new PrismaClient();

export async function getDailyRewardState(userId: string): Promise<DailyRewardState | null> {
  const dailyReward = await prisma.dailyReward.findUnique({
    where: { userId }
  });

  if (!dailyReward) {
    return {
      current_day: 1,
      total_coins: 0,
      can_claim: true,
      cooldown_until: null,
      coins_to_win: REWARD_SCHEDULE[0],
      reset_needed: false
    };
  }

  let canClaim: boolean = false;
  let cooldownUntil: Date | null = null;
  let resetNeeded: boolean = false;

  if (dailyReward.lastClaimedAt) {
    const elapsed: number = Date.now() - dailyReward.lastClaimedAt.getTime();
    
    if (elapsed > RESET_THRESHOLD_MS) {
      resetNeeded = true;
      canClaim = true;
    } else if (elapsed >= COOLDOWN_MS) {
      canClaim = true;
    } else {
      cooldownUntil = new Date(dailyReward.lastClaimedAt.getTime() + COOLDOWN_MS);
    }
  } else {
    canClaim = true;
  }

  const currentDay: number = dailyReward.currentDay || 1;
  const coinsToWin: number = REWARD_SCHEDULE[currentDay - 1] || REWARD_SCHEDULE[0];

  return {
    current_day: currentDay,
    total_coins: dailyReward.totalCoins || 0,
    can_claim: canClaim,
    cooldown_until: cooldownUntil ? cooldownUntil.toISOString() : null,
    coins_to_win: coinsToWin,
    reset_needed: resetNeeded,
    last_claimed_at: dailyReward.lastClaimedAt?.toISOString()
  };
}

export async function claimDailyReward(userId: string): Promise<ClaimResult> {
  return await prisma.$transaction(async (tx) => {
    let dailyReward = await tx.dailyReward.findUnique({
      where: { userId }
    });
    
    if (!dailyReward) {
      const user = await tx.user.create({
        data: { id: userId, createdAt: new Date() }
      });
      
      dailyReward = await tx.dailyReward.create({
        data: {
          userId,
          currentDay: 1,
          totalCoins: 0,
          cycleStartedAt: new Date()
        }
      });
    }

    const now: number = Date.now();
    let currentDay: number = dailyReward.currentDay || 1;
    let resetOccurred: boolean = false;

    if (dailyReward.lastClaimedAt) {
      const elapsed: number = now - dailyReward.lastClaimedAt.getTime();

      if (elapsed < COOLDOWN_MS) {
        const error: CooldownError = new Error('COOLDOWN_ACTIVE') as CooldownError;
        error.code = 'COOLDOWN_ACTIVE';
        error.retryAfter = COOLDOWN_MS - elapsed;
        throw error;
      }

      if (elapsed > RESET_THRESHOLD_MS) {
        currentDay = 1;
        resetOccurred = true;
      } else {
        currentDay = currentDay + 1;
        if (currentDay > MAX_DAY) {
          currentDay = 1;
        }
      }
    }

    const coinsAwarded: number = REWARD_SCHEDULE[currentDay - 1] || REWARD_SCHEDULE[0];

    await tx.dailyReward.update({
      where: { id: dailyReward.id },
      data: {
        currentDay,
        lastClaimedAt: new Date(),
        totalCoins: (dailyReward.totalCoins || 0) + coinsAwarded,
        cycleStartedAt: resetOccurred ? new Date() : dailyReward.cycleStartedAt
      }
    });

    return {
      success: true,
      coins_awarded: coinsAwarded,
      current_day: currentDay,
      total_coins: (dailyReward.totalCoins || 0) + coinsAwarded,
      reset_occurred: resetOccurred
    };
  });
}
