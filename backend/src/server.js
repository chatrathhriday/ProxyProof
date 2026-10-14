import 'dotenv/config';
import { initDb } from './db.js';
import { createApp } from './app.js';

await initDb();
const port = process.env.PORT || 3000;
createApp().listen(port, () => console.log(`ProxyProof API on http://localhost:${port}`));
