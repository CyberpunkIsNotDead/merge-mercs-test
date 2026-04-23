export interface DailyRewardRecord {
  id: string;
  currentDay: number;
  lastClaimedAt: Date | null;
  totalCoins: number;
  cycleStartedAt: Date;
}

export interface DailyRewardState {
  current_day: number;
  total_coins: number;
  can_claim: boolean;
  cooldown_until: string | null;
  coins_to_win: number;
  reset_needed: boolean;
  last_claimed_at?: string;
}

export interface ClaimResult {
  success: boolean;
  coins_awarded: number;
  current_day: number;
  total_coins: number;
  reset_occurred: boolean;
}

export interface CooldownError extends Error {
  code: 'COOLDOWN_ACTIVE';
  retryAfter: number;
}
