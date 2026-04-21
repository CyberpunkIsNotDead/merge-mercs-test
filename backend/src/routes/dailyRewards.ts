import { Router, Request, Response } from 'express';
import { getDailyRewardState, claimDailyReward } from '../services/dailyRewardService.js';
import { authMiddleware } from '../middleware/authMiddleware.js';
import type { CooldownError } from '../types/index.js';

const router: Router = Router();

router.get('/', authMiddleware, async (req: Request & { userId?: string }, res: Response): Promise<void> => {
  try {
    if (!req.userId) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    
    const state = await getDailyRewardState(req.userId);
    
    if (!state) {
      res.status(404).json({ error: 'No daily reward record found' });
      return;
    }

    res.json(state);
  } catch (err) {
    console.error('Get daily reward state error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/claim', authMiddleware, async (req: Request & { userId?: string }, res: Response): Promise<void> => {
  try {
    if (!req.userId) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    
    const result = await claimDailyReward(req.userId);

    res.json({
      success: result.success,
      coins_awarded: result.coins_awarded,
      current_day: result.current_day,
      total_coins: result.total_coins,
      reset_occurred: result.reset_occurred || false
    });
  } catch (err) {
    if (err instanceof Error && 'code' in err && (err as CooldownError).code === 'COOLDOWN_ACTIVE') {
      const cooldownErr = err as CooldownError;
      const retryAfter: number = Math.ceil(cooldownErr.retryAfter / 1000);
      
      res.status(409).json({
        success: false,
        error: 'COOLDOWN_ACTIVE',
        message: `Come back in ${Math.ceil(retryAfter / 60)} minutes`,
        retry_after_seconds: Math.ceil(cooldownErr.retryAfter)
      });
      return;
    }

    console.error('Claim daily reward error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
