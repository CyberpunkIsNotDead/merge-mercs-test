import { Router, Request, Response } from 'express';
import { createGuest } from '../services/authService.js';
import type { GuestResponse } from '../types/index.js';

const router: Router = Router();

router.post('/guest', async (req: Request, res: Response): Promise<void> => {
  try {
    const result: GuestResponse = await createGuest();
    res.json({
      user_id: result.user_id,
      token: result.token
    });
  } catch (err) {
    console.error('Auth guest error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
