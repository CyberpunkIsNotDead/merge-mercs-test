import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';
import type { GuestResponse, AuthVerificationResult } from '../types/index.js';

const prisma = new PrismaClient();

const JWT_SECRET: string = process.env.JWT_SECRET || 'daily-rewards-secret-key-change-in-production-2024';
const JWT_EXPIRES_IN: string = process.env.JWT_EXPIRES_IN || '1h';

export async function createGuest(): Promise<GuestResponse> {
  const userId: string = crypto.randomUUID();
  
  const token: string = jwt.sign({ user_id: userId }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN } as any);
  const tokenHash: string = await bcrypt.hash(token, 10);

  const user = await prisma.user.create({
    data: {
      id: userId,
      tokenHash,
      dailyReward: {
        create: {
          currentDay: 1,
          totalCoins: 0,
        }
      }
    },
    include: {
      dailyReward: true
    }
  });

  return { user_id: userId, token };
}

export async function verifyToken(authorizationHeader: string | undefined): Promise<AuthVerificationResult> {
  if (!authorizationHeader || !authorizationHeader.startsWith('Bearer ')) {
    throw new Error('Invalid or missing authorization header');
  }

  const token: string = authorizationHeader.substring(7);
  
  let decoded: { user_id: string };
  try {
    decoded = jwt.verify(token, JWT_SECRET) as { user_id: string };
  } catch (err) {
    throw new Error('Token expired or invalid');
  }

  const user = await prisma.user.findUnique({
    where: { id: decoded.user_id },
    include: { dailyReward: true }
  });

  if (!user) {
    throw new Error('User not found');
  }

  const isValid: boolean = await bcrypt.compare(token, user.tokenHash);
  if (!isValid) {
    throw new Error('Token invalidated');
  }

  return { userId: decoded.user_id, dailyReward: user.dailyReward };
}

export async function cleanupExpiredTokens(): Promise<void> {
  const now: Date = new Date();
  
  await prisma.$executeRaw`
    DELETE FROM "User" 
    WHERE id NOT IN (
      SELECT DISTINCT d."userId" 
      FROM "DailyReward" d
    )
    AND createdAt < NOW() - INTERVAL '24 hours'
  `;
}
