import express from 'express';
import cors from 'cors';
import { authRouter } from './auth.js';
import { coursesRouter } from './routes/courses.js';
import { sessionsRouter } from './routes/sessions.js';
import { attendanceRouter } from './routes/attendance.js';

export function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '50kb' }));

  app.get('/health', (req, res) => res.json({ ok: true }));
  app.use('/auth', authRouter);
  app.use('/courses', coursesRouter);
  app.use('/sessions', sessionsRouter);
  app.use('/attendance', attendanceRouter);

  // Express 5 forwards async errors here.
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  });
  return app;
}
