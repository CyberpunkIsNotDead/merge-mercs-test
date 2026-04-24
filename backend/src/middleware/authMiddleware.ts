import { Request, Response, NextFunction } from 'express';
import { verifyToken, type AuthPayload } from '../services/authService.js';

export interface AuthRequest extends Request {
  auth?: AuthPayload;
}

export function authMiddleware(req: AuthRequest, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    res.status(401).json({ error: 'UNAUTHORIZED', message: 'Authorization header required' });
    return;
  }

  const token = authHeader.split(' ')[1];
  
  if (!token) {
    res.status(401).json({ error: 'UNAUTHORIZED', message: 'Token missing' });
    return;
  }

  const payload = verifyToken(token);
  
  if (!payload) {
    res.status(401).json({ error: 'INVALID_TOKEN', message: 'Invalid or expired token' });
    return;
  }

  req.auth = payload;
  next();
}
