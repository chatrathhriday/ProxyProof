// Live updates for the organiser dashboard over Socket.IO.
// A dashboard joins room "session:<id>" (only if it owns the session) and receives:
//   "roster" -> someone's status changed (mark, manual add/remove, close): refetch roster
//   "seen"   -> a sighting arrived: { studentId, at, rssi } (cheap, applied locally)
import { Server } from 'socket.io';
import { one } from './db.js';
import { verifyJwt } from './auth.js';

let io = null;

export function attachLive(httpServer) {
  io = new Server(httpServer, { cors: { origin: '*' } });

  // Same JWT as the REST API, sent in the socket handshake.
  io.use((socket, next) => {
    try {
      socket.user = verifyJwt(socket.handshake.auth?.token || '');
      next();
    } catch {
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', (socket) => {
    socket.on('watch', async (sessionId, ack) => {
      const s = await one('SELECT organiser_id FROM sessions WHERE id = $1', [sessionId]);
      const allowed = s && (socket.user.role === 'admin' || s.organiser_id === socket.user.id);
      if (allowed) socket.join(`session:${sessionId}`);
      ack?.({ ok: !!allowed });
    });
    socket.on('unwatch', (sessionId) => socket.leave(`session:${sessionId}`));
  });
  return io;
}

export function emit(sessionId, event, data = {}) {
  io?.to(`session:${sessionId}`).emit(event, { sessionId, ...data });
}
