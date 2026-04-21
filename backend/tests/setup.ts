import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

afterEach(async () => {
  await prisma.dailyReward.deleteMany();
  await prisma.user.deleteMany();
});
