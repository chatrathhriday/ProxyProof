import 'dotenv/config';
import http from 'node:http';
import { initDb } from './db.js';
import { createApp } from './app.js';
import { attachLive } from './live.js';
import { seedDemo } from './seed.js';

await initDb();
if (process.env.SEED_DEMO === 'true') await seedDemo();
if (process.env.NODE_ENV === 'production' && !process.env.JWT_SECRET) throw new Error('JWT_SECRET must be set in production');

const port = process.env.PORT || 3000;
const server = http.createServer(createApp());
attachLive(server);
server.listen(port, () => console.log(`ProxyProof API on http://localhost:${port}`));
