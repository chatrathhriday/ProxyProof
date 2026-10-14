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
  app.get('/', (req, res) =>
    res.type('html').send(`<!doctype html><meta name="viewport" content="width=device-width">
      <body style="font:16px system-ui;max-width:640px;margin:40px auto;padding:0 16px">
      <h1>ProxyProof API</h1><p>✅ Running. This is the backend only; the app and dashboard talk to it.</p>
      <ul><li>POST /auth/register, /auth/login</li><li>GET/POST /courses, POST /courses/:id/enroll</li>
      <li>POST /sessions, GET /sessions/:id, GET /sessions/:id/beacon, POST /sessions/:id/close</li>
      <li>POST /attendance/sighting</li></ul>`)
  );
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
