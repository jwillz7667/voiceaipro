import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { parse as parseUrl } from 'url';

import config, { validateEnvironment } from './config/environment.js';
import logger, { requestLogger, createLogger } from './utils/logger.js';
import { testConnection, closePool, getPoolStats } from './db/pool.js';
import connectionManager from './websocket/connectionManager.js';
import { handleTwilioMediaStream } from './websocket/twilioMediaHandler.js';
import { handleIOSClientConnection, handleEventStreamConnection } from './websocket/iosClientHandler.js';

import tokenRouter from './routes/token.js';
import twimlRouter from './routes/twiml.js';
import callsRouter from './routes/calls.js';
import recordingsRouter from './routes/recordings.js';
import promptsRouter from './routes/prompts.js';

const appLogger = createLogger('app');

try {
  validateEnvironment();
  appLogger.info('Environment validation passed');
} catch (error) {
  appLogger.error('Environment validation failed', error);
  process.exit(1);
}

const app = express();
const server = createServer(app);

app.set('trust proxy', config.server.trustProxy ? 1 : false);

app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));

app.use(cors({
  origin: config.server.corsOrigins.includes('*') ? true : config.server.corsOrigins,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-ID'],
}));

app.use(compression());

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.use(requestLogger());

const apiLimiter = rateLimit({
  windowMs: config.server.rateLimitWindowMs,
  max: config.server.rateLimitMax,
  message: {
    error: {
      code: 'E005',
      message: 'Too many requests, please try again later',
    },
  },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api/', apiLimiter);

// Simple health check for Railway (no async operations)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Detailed status endpoint (with async database check)
app.get('/status', async (req, res) => {
  const dbConnected = await testConnection().catch(() => false);
  const poolStats = getPoolStats();
  const activeConnections = connectionManager.getStats();

  // Check Twilio SDK configuration
  const twilioSdkConfigured = !!(config.twilio?.apiKey && config.twilio?.apiSecret && config.twilio?.twimlAppSid);
  const twilioWebhooksConfigured = !!(config.twilio?.accountSid && config.twilio?.authToken);

  const status = dbConnected ? 'healthy' : 'degraded';

  res.status(dbConnected ? 200 : 503).json({
    status,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || '1.0.0',
    database: {
      connected: dbConnected,
      pool: poolStats,
    },
    twilio: {
      sdkTokens: twilioSdkConfigured,
      webhooks: twilioWebhooksConfigured,
    },
    connections: {
      activeSessions: activeConnections.activeSessions,
      totalSessions: activeConnections.totalSessions,
      iosClients: activeConnections.iosClients,
    },
  });
});

app.get('/', (req, res) => {
  res.json({
    name: 'VoiceAI Bridge Server',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: '/health',
      api: {
        token: '/api/token',
        calls: '/api/calls',
        recordings: '/api/recordings',
        prompts: '/api/prompts',
        session: '/api/session',
      },
      websocket: {
        mediaStream: '/media-stream',
        iosClient: '/ios-client',
        events: '/events/:callId',
      },
      twiml: {
        outgoing: '/twiml/outgoing',
        incoming: '/twiml/incoming',
        status: '/twiml/status',
      },
    },
  });
});

app.use('/api/token', tokenRouter);
app.use('/twiml', twimlRouter);
app.use('/api/calls', callsRouter);
app.use('/api/recordings', recordingsRouter);
app.use('/api/prompts', promptsRouter);

app.post('/api/session/config', (req, res) => {
  const { call_sid, config: sessionConfig } = req.body;

  if (!call_sid) {
    return res.status(400).json({
      error: {
        code: 'MISSING_CALL_SID',
        message: 'call_sid is required',
      },
    });
  }

  const session = connectionManager.getSession(call_sid);
  if (!session) {
    return res.status(404).json({
      error: {
        code: 'SESSION_NOT_FOUND',
        message: `No active session for call: ${call_sid}`,
      },
    });
  }

  session.updateConfig(sessionConfig);

  res.json({
    success: true,
    call_sid,
    config: session.config,
  });
});

app.get('/api/stats', (req, res) => {
  const poolStats = getPoolStats();
  const connectionStats = connectionManager.getStats();

  res.json({
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    database: poolStats,
    connections: connectionStats,
  });
});

app.use((req, res, next) => {
  res.status(404).json({
    error: {
      code: 'NOT_FOUND',
      message: `Route not found: ${req.method} ${req.path}`,
    },
  });
});

app.use((err, req, res, next) => {
  appLogger.error('Unhandled error', err);

  res.status(err.status || 500).json({
    error: {
      code: err.code || 'INTERNAL_ERROR',
      message: config.isProduction() ? 'An internal error occurred' : err.message,
      ...(config.isDevelopment() && { stack: err.stack }),
    },
  });
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const { pathname } = parseUrl(request.url, true);

  appLogger.debug('WebSocket upgrade request', { pathname });

  if (pathname === '/media-stream') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      handleTwilioMediaStream(ws, request);
    });
  } else if (pathname === '/ios-client') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      handleIOSClientConnection(ws, request);
    });
  } else if (pathname.startsWith('/events/')) {
    const callId = pathname.replace('/events/', '');
    wss.handleUpgrade(request, socket, head, (ws) => {
      handleEventStreamConnection(ws, request, callId);
    });
  } else {
    appLogger.warn('Unknown WebSocket path', { pathname });
    socket.destroy();
  }
});

let isShuttingDown = false;

async function gracefulShutdown(signal) {
  if (isShuttingDown) {
    appLogger.warn('Shutdown already in progress');
    return;
  }

  isShuttingDown = true;
  appLogger.info(`Received ${signal}, starting graceful shutdown`);

  const shutdownTimeout = setTimeout(() => {
    appLogger.error('Shutdown timeout exceeded, forcing exit');
    process.exit(1);
  }, 30000);

  try {
    appLogger.info('Closing active connections');
    connectionManager.cleanup();

    appLogger.info('Closing WebSocket server');
    wss.close();

    appLogger.info('Closing HTTP server');
    await new Promise((resolve, reject) => {
      server.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });

    appLogger.info('Closing database pool');
    await closePool();

    clearTimeout(shutdownTimeout);
    appLogger.info('Graceful shutdown complete');
    process.exit(0);
  } catch (error) {
    appLogger.error('Error during shutdown', error);
    clearTimeout(shutdownTimeout);
    process.exit(1);
  }
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

process.on('uncaughtException', (error) => {
  appLogger.error('Uncaught exception', error);
  gracefulShutdown('uncaughtException');
});

process.on('unhandledRejection', (reason, promise) => {
  appLogger.error('Unhandled rejection', { reason, promise });
});

async function startServer() {
  try {
    appLogger.info('Testing database connection');
    const dbConnected = await testConnection();

    if (!dbConnected) {
      if (config.isProduction()) {
        appLogger.error('Database connection failed - required in production');
        process.exit(1);
      } else {
        appLogger.warn('Database connection failed - running in degraded mode (some features disabled)');
        appLogger.warn('For full functionality, set DATABASE_URL to your public Railway PostgreSQL URL');
        appLogger.warn('Get the public URL from Railway Dashboard → PostgreSQL → Connect → Public URL');
      }
    }

    server.listen(config.port, () => {
      appLogger.info(`Server started`, {
        port: config.port,
        environment: config.nodeEnv,
        pid: process.pid,
      });

      // Check Twilio SDK configuration
      const hasTwilioSdk = config.twilio.apiKey && config.twilio.apiSecret && config.twilio.twimlAppSid;
      if (!hasTwilioSdk) {
        appLogger.warn('Twilio SDK not fully configured - iOS client tokens disabled');
        appLogger.warn('Missing: TWILIO_API_KEY, TWILIO_API_SECRET, and/or TWIML_APP_SID');
        appLogger.warn('Inbound calls via webhooks will still work with Account SID/Auth Token');
      } else {
        appLogger.info('Twilio SDK configured - iOS client tokens enabled');
      }

      appLogger.info('WebSocket endpoints available', {
        mediaStream: `/media-stream`,
        iosClient: `/ios-client`,
        events: `/events/:callId`,
      });

      appLogger.info('REST API endpoints available', {
        base: `/api`,
        health: `/health`,
        twiml: `/twiml`,
      });
    });

    server.on('error', (error) => {
      if (error.code === 'EADDRINUSE') {
        appLogger.error(`Port ${config.port} is already in use`);
      } else {
        appLogger.error('Server error', error);
      }
      process.exit(1);
    });
  } catch (error) {
    appLogger.error('Failed to start server', error);
    process.exit(1);
  }
}

startServer();

export { app, server, wss };
