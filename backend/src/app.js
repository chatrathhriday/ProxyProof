import express from 'express';
import cors from 'cors';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { authRouter } from './auth.js';
import { coursesRouter } from './routes/courses.js';
import { sessionsRouter } from './routes/sessions.js';
import { attendanceRouter } from './routes/attendance.js';
import { devicesRouter } from './routes/devices.js';

// The organiser dashboard is built into dashboard/dist and served from this same server:
// one deploy, one URL, no cross-origin setup.
const DASHBOARD = fileURLToPath(new URL('../../dashboard/dist', import.meta.url));

export function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '50kb' }));

  app.get('/health', (req, res) => res.json({ ok: true }));
  app.use('/auth', authRouter);
  app.use('/courses', coursesRouter);
  app.use('/sessions', sessionsRouter);
  app.use('/attendance', attendanceRouter);
  app.use('/devices', devicesRouter);

  if (existsSync(DASHBOARD)) {
    app.use(express.static(DASHBOARD));
  } else {
    app.get('/', (req, res) =>
      res.type('html').send(`<!doctype html><meta name="viewport" content="width=device-width">
        <body style="font:16px system-ui;max-width:640px;margin:40px auto;padding:0 16px">
        <h1>ProxyProof API</h1><p>✅ Running. Dashboard not built yet: <code>cd dashboard && npm run build</code></p>`)
    );
  }

  // Express 5 forwards async errors here.
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  });
  return app;
}
