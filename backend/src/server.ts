import express from 'express';
import cors from 'cors';
const authRoutes = await import('./routes/auth.js');
const dailyRewardRoutes = await import('./routes/dailyRewards.js');

const app: express.Application = express();
const PORT: number = parseInt(process.env.PORT || '3000', 10);

app.use(cors());
app.use(express.json());

app.use('/auth', authRoutes.default);
app.use('/daily-rewards', dailyRewardRoutes.default);

app.get('/health', (req: express.Request, res: express.Response): void => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

let server: ReturnType<typeof app.listen> | undefined;
if (process.env.NODE_ENV !== 'test') {
  server = app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });
}

export { app };
export default app;
