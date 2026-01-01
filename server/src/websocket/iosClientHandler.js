import { createLogger } from '../utils/logger.js';
import connectionManager from './connectionManager.js';
import {
  updateSessionConfig,
  interruptResponse,
  createManualResponse,
  sendTextMessage,
} from './openaiRealtimeHandler.js';

const logger = createLogger('ios-client');

export function handleIOSClientConnection(ws, request) {
  let deviceId = null;
  let authenticatedAt = null;

  logger.info('New iOS client connection', {
    ip: request.socket.remoteAddress,
    headers: {
      userAgent: request.headers['user-agent'],
    },
  });

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      handleIOSMessage(ws, message, { deviceId, authenticatedAt });
    } catch (error) {
      logger.error('Error processing iOS client message', { error: error.message });
      sendError(ws, 'PARSE_ERROR', 'Invalid JSON message');
    }
  });

  ws.on('close', (code, reason) => {
    logger.info('iOS client disconnected', {
      deviceId,
      code,
      reason: reason?.toString(),
    });

    if (deviceId) {
      connectionManager.unregisterIOSClient(deviceId);
    }
  });

  ws.on('error', (error) => {
    logger.error('iOS client WebSocket error', {
      deviceId,
      error: error.message,
    });
  });

  function handleIOSMessage(ws, message, context) {
    const { type, payload } = message;

    switch (type) {
      case 'auth':
        handleAuth(ws, payload, context);
        break;

      case 'subscribe':
        handleSubscribe(ws, payload, context);
        break;

      case 'unsubscribe':
        handleUnsubscribe(ws, payload, context);
        break;

      case 'session.update':
        handleSessionUpdate(ws, payload, context);
        break;

      case 'call.interrupt':
        handleInterrupt(ws, payload, context);
        break;

      case 'call.trigger_response':
        handleTriggerResponse(ws, payload, context);
        break;

      case 'call.send_text':
        handleSendText(ws, payload, context);
        break;

      case 'call.end':
        handleEndCall(ws, payload, context);
        break;

      case 'ping':
        sendMessage(ws, 'pong', { timestamp: Date.now() });
        break;

      case 'get.sessions':
        handleGetSessions(ws, context);
        break;

      case 'get.session':
        handleGetSession(ws, payload, context);
        break;

      case 'get.events':
        handleGetEvents(ws, payload, context);
        break;

      default:
        logger.warn('Unknown iOS client message type', { type });
        sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${type}`);
    }
  }

  function handleAuth(ws, payload, context) {
    const { device_id, token } = payload || {};

    if (!device_id) {
      sendError(ws, 'AUTH_FAILED', 'Missing device_id');
      return;
    }

    deviceId = device_id;
    context.deviceId = device_id;
    authenticatedAt = new Date();
    context.authenticatedAt = authenticatedAt;

    connectionManager.registerIOSClient(deviceId, ws);

    sendMessage(ws, 'auth.success', {
      device_id: deviceId,
      authenticated_at: authenticatedAt.toISOString(),
    });

    logger.info('iOS client authenticated', { deviceId });
  }

  function handleSubscribe(ws, payload, context) {
    const { call_sid } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (session) {
      session.setIOSConnection(ws);
      sendMessage(ws, 'subscribed', {
        call_sid,
        session: session.toJSON(),
      });
    } else {
      connectionManager.subscribeToEvents(call_sid, ws);
      sendMessage(ws, 'subscribed', {
        call_sid,
        session: null,
        message: 'Subscribed for future events',
      });
    }

    logger.info('iOS client subscribed to call', {
      deviceId: context.deviceId,
      callSid: call_sid,
    });
  }

  function handleUnsubscribe(ws, payload, context) {
    const { call_sid } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    connectionManager.unsubscribeFromEvents(call_sid, ws);
    sendMessage(ws, 'unsubscribed', { call_sid });

    logger.info('iOS client unsubscribed from call', {
      deviceId: context.deviceId,
      callSid: call_sid,
    });
  }

  function handleSessionUpdate(ws, payload, context) {
    const { call_sid, config } = payload || {};

    if (!call_sid || !config) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid or config');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (!session) {
      sendError(ws, 'SESSION_NOT_FOUND', `No active session for call: ${call_sid}`);
      return;
    }

    updateSessionConfig(session, config);

    sendMessage(ws, 'session.updated', {
      call_sid,
      config: session.config,
    });

    logger.info('Session config updated via iOS client', {
      deviceId: context.deviceId,
      callSid: call_sid,
    });
  }

  function handleInterrupt(ws, payload, context) {
    const { call_sid } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (!session) {
      sendError(ws, 'SESSION_NOT_FOUND', `No active session for call: ${call_sid}`);
      return;
    }

    interruptResponse(session);

    sendMessage(ws, 'call.interrupted', { call_sid });

    logger.info('Call interrupted via iOS client', {
      deviceId: context.deviceId,
      callSid: call_sid,
    });
  }

  function handleTriggerResponse(ws, payload, context) {
    const { call_sid } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (!session) {
      sendError(ws, 'SESSION_NOT_FOUND', `No active session for call: ${call_sid}`);
      return;
    }

    createManualResponse(session);

    sendMessage(ws, 'response.triggered', { call_sid });

    logger.info('Response triggered via iOS client', {
      deviceId: context.deviceId,
      callSid: call_sid,
    });
  }

  function handleSendText(ws, payload, context) {
    const { call_sid, text, role } = payload || {};

    if (!call_sid || !text) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid or text');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (!session) {
      sendError(ws, 'SESSION_NOT_FOUND', `No active session for call: ${call_sid}`);
      return;
    }

    sendTextMessage(session, text, role || 'user');

    sendMessage(ws, 'text.sent', { call_sid, text });

    logger.info('Text sent via iOS client', {
      deviceId: context.deviceId,
      callSid: call_sid,
      textLength: text.length,
    });
  }

  function handleEndCall(ws, payload, context) {
    const { call_sid, reason } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const destroyed = connectionManager.destroySession(call_sid, reason || 'ios_client_end');

    if (destroyed) {
      sendMessage(ws, 'call.ended', { call_sid, reason });
      logger.info('Call ended via iOS client', {
        deviceId: context.deviceId,
        callSid: call_sid,
        reason,
      });
    } else {
      sendError(ws, 'SESSION_NOT_FOUND', `No active session for call: ${call_sid}`);
    }
  }

  function handleGetSessions(ws, context) {
    const sessions = connectionManager.getActiveSessions().map((s) => s.toJSON());
    sendMessage(ws, 'sessions', { sessions });
  }

  function handleGetSession(ws, payload, context) {
    const { call_sid } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (session) {
      sendMessage(ws, 'session', {
        session: session.toJSON(),
        stats: session.getStats(),
      });
    } else {
      sendError(ws, 'SESSION_NOT_FOUND', `No session for call: ${call_sid}`);
    }
  }

  function handleGetEvents(ws, payload, context) {
    const { call_sid, limit, offset } = payload || {};

    if (!call_sid) {
      sendError(ws, 'INVALID_PAYLOAD', 'Missing call_sid');
      return;
    }

    const session = connectionManager.getSession(call_sid);
    if (!session) {
      sendError(ws, 'SESSION_NOT_FOUND', `No session for call: ${call_sid}`);
      return;
    }

    const eventLimit = Math.min(limit || 100, 500);
    const eventOffset = offset || 0;
    const events = session.events.slice(eventOffset, eventOffset + eventLimit);

    sendMessage(ws, 'events', {
      call_sid,
      events,
      total: session.events.length,
      limit: eventLimit,
      offset: eventOffset,
    });
  }
}

function sendMessage(ws, type, payload) {
  if (ws.readyState !== 1) {
    return;
  }

  const message = JSON.stringify({
    type,
    timestamp: new Date().toISOString(),
    payload,
  });

  try {
    ws.send(message);
  } catch (error) {
    logger.error('Failed to send message to iOS client', { type, error: error.message });
  }
}

function sendError(ws, code, message) {
  sendMessage(ws, 'error', { code, message });
}

export function handleEventStreamConnection(ws, request, callSid) {
  logger.info('New event stream connection', { callSid });

  const session = connectionManager.getSession(callSid);

  if (session) {
    sendMessage(ws, 'connected', {
      call_sid: callSid,
      session: session.toJSON(),
    });

    const recentEvents = session.events.slice(-50);
    recentEvents.forEach((event) => {
      sendMessage(ws, 'event', event);
    });
  }

  connectionManager.subscribeToEvents(callSid, ws);

  ws.on('close', () => {
    logger.info('Event stream connection closed', { callSid });
    connectionManager.unsubscribeFromEvents(callSid, ws);
  });

  ws.on('error', (error) => {
    logger.error('Event stream error', { callSid, error: error.message });
  });
}

export default {
  handleIOSClientConnection,
  handleEventStreamConnection,
};
