import 'dotenv/config';
import http from 'node:http';
import { initDb } from './db.js';
import { createApp } from './app.js';
import { attachLive } from './live.js';

await initDb();
const port = process.env.PORT || 3000;
const server = http.createServer(createApp());
attachLive(server);
server.listen(port, () => console.log(`ProxyProof API on http://localhost:${port}`));
