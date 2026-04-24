import { Router, Request, Response } from 'express';
import { createGuestUser } from '../services/authService.js';

const router: Router = Router();

router.post('/guest', (_req: Request, res: Response): void => {
  const { user_id, token } = createGuestUser();
  
  res.json({ user_id, token });
});

export default router;
