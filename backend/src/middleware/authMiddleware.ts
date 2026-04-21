import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../services/authService.js';
import type { AuthVerificationResult } from '../types/index.js';

export async function authMiddleware(
  req: Request & { userId?: string; dailyReward?: any },
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const result: AuthVerificationResult = await verifyToken(req.headers.authorization);
    req.userId = result.userId;
    req.dailyReward = result.dailyReward;
    next();
  } catch (err) {
    if (err instanceof Error && 
        (err.message === 'Invalid or missing authorization header' || 
         err.message === 'User not found')) {
      res.status(401).json({ error: 'Unauthorized', message: err.message });
      return;
    }
    
    if (err instanceof Error && 
        (err.message === 'Token expired or invalid' || 
         err.message === 'Token invalidated')) {
      res.status(401).json({ error: 'Unauthorized', message: 'Authentication failed' });
      return;
    }
    
    console.error('Auth middleware error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}
