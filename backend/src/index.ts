import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { authRouter } from './routes/auth.js';
import { workoutsRouter } from './routes/workouts.js';
import { goalsRouter } from './routes/goals.js';
import { plansRouter } from './routes/plans.js';
import { profileRouter } from './routes/profile.js';
import { authenticateToken } from './middleware/auth.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Health check (public)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Auth routes (public)
app.use('/auth', authRouter);

// Protected routes (require authentication)
app.use('/workouts', authenticateToken, workoutsRouter);
app.use('/goals', authenticateToken, goalsRouter);
app.use('/plans', authenticateToken, plansRouter);
app.use('/profile', authenticateToken, profileRouter);

// Error handler
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Error:', err);
  res.status(500).json({ error: 'Internal server error', message: err.message });
});

app.listen(PORT, () => {
  console.log(`🚀 Stride API running on port ${PORT}`);
});
