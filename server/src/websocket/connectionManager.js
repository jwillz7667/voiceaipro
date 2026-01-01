import { v4 as uuidv4 } from 'uuid';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('connections');

class CallSession {
  constructor(callSid, options = {}) {
    this.id = uuidv4();
    this.callSid = callSid;
    this.direction = options.direction || 'outbound';
    this.phoneNumber = options.phoneNumber || null;
    this.promptId = options.promptId || null;
    this.userId = options.userId || null;
    this.createdAt = new Date();
    this.status = 'initializing';

    this.twilioWs = null;
    this.openaiWs = null;
    this.iosWs = null;
    this.streamSid = null;

    this.config = {
      model: 'gpt-realtime',
      voice: 'marin',
      voiceSpeed: 1.0,
      vadType: 'semantic_vad',
      vadConfig: {
        eagerness: 'high',
        createResponse: true,
        interruptResponse: true,
      },
      noiseReduction: null,
      transcriptionModel: 'whisper-1',
      temperature: 0.8,
      maxOutputTokens: 4096,
      instructions: '',
      ...options.config,
    };

    this.events = [];
    this.transcripts = [];
    this.audioBufferQueue = [];
    this.isRecording = options.isRecording ?? true;
    this.recordingBuffer = this.isRecording ? [] : null;
  }

  setTwilioConnection(ws, streamSid) {
    this.twilioWs = ws;
    this.streamSid = streamSid;
    this.updateStatus('twilio_connected');
    logger.info('Twilio connection established', { callSid: this.callSid, streamSid });
  }

  setOpenAIConnection(ws) {
    this.openaiWs = ws;
    this.updateStatus('openai_connected');
    logger.info('OpenAI connection established', { callSid: this.callSid });
  }

  setIOSConnection(ws) {
    this.iosWs = ws;
    logger.info('iOS client connection established', { callSid: this.callSid });
  }

  updateStatus(status) {
    const previousStatus = this.status;
    this.status = status;
    logger.debug('Session status changed', {
      callSid: this.callSid,
      previousStatus,
      newStatus: status,
    });
    this.broadcastEvent('session.status', { status, previousStatus });
  }

  updateConfig(newConfig) {
    this.config = { ...this.config, ...newConfig };
    logger.info('Session config updated', { callSid: this.callSid, config: this.config });
    this.broadcastEvent('config.updated', { config: this.config });
  }

  addEvent(eventType, direction, payload = null) {
    const event = {
      id: uuidv4(),
      timestamp: new Date(),
      callSid: this.callSid,
      eventType,
      direction,
      payload,
    };
    this.events.push(event);

    if (this.events.length > 1000) {
      this.events = this.events.slice(-500);
    }

    return event;
  }

  addTranscript(speaker, content, timestampMs = null) {
    const transcript = {
      id: uuidv4(),
      speaker,
      content,
      timestampMs: timestampMs ?? Date.now() - this.createdAt.getTime(),
      createdAt: new Date(),
    };
    this.transcripts.push(transcript);
    return transcript;
  }

  addRecordingChunk(audioData) {
    if (this.isRecording && this.recordingBuffer) {
      this.recordingBuffer.push({
        timestamp: Date.now(),
        data: audioData,
      });
    }
  }

  getRecordingBuffer() {
    return this.recordingBuffer || [];
  }

  broadcastEvent(eventType, data) {
    const event = this.addEvent(eventType, 'outgoing', data);
    const message = JSON.stringify({
      type: eventType,
      callSid: this.callSid,
      timestamp: event.timestamp.toISOString(),
      data,
    });

    if (this.iosWs && this.iosWs.readyState === 1) {
      try {
        this.iosWs.send(message);
      } catch (error) {
        logger.error('Failed to send event to iOS client', { callSid: this.callSid, error });
      }
    }

    return event;
  }

  sendToTwilio(message) {
    if (this.twilioWs && this.twilioWs.readyState === 1) {
      try {
        const payload = typeof message === 'string' ? message : JSON.stringify(message);
        this.twilioWs.send(payload);
        return true;
      } catch (error) {
        logger.error('Failed to send to Twilio', { callSid: this.callSid, error });
        return false;
      }
    }
    return false;
  }

  sendToOpenAI(message) {
    if (this.openaiWs && this.openaiWs.readyState === 1) {
      try {
        const payload = typeof message === 'string' ? message : JSON.stringify(message);
        this.openaiWs.send(payload);
        return true;
      } catch (error) {
        logger.error('Failed to send to OpenAI', { callSid: this.callSid, error });
        return false;
      }
    }
    return false;
  }

  isFullyConnected() {
    return (
      this.twilioWs?.readyState === 1 &&
      this.openaiWs?.readyState === 1
    );
  }

  getStats() {
    return {
      id: this.id,
      callSid: this.callSid,
      direction: this.direction,
      phoneNumber: this.phoneNumber,
      status: this.status,
      createdAt: this.createdAt,
      durationMs: Date.now() - this.createdAt.getTime(),
      eventCount: this.events.length,
      transcriptCount: this.transcripts.length,
      twilioConnected: this.twilioWs?.readyState === 1,
      openaiConnected: this.openaiWs?.readyState === 1,
      iosConnected: this.iosWs?.readyState === 1,
    };
  }

  toJSON() {
    return {
      id: this.id,
      callSid: this.callSid,
      direction: this.direction,
      phoneNumber: this.phoneNumber,
      status: this.status,
      createdAt: this.createdAt.toISOString(),
      config: this.config,
    };
  }
}

class ConnectionManager {
  constructor() {
    this.sessions = new Map();
    this.iosClients = new Map();
    this.eventSubscribers = new Map();
  }

  createSession(callSid, options = {}) {
    if (this.sessions.has(callSid)) {
      logger.warn('Session already exists, returning existing', { callSid });
      return this.sessions.get(callSid);
    }

    const session = new CallSession(callSid, options);
    this.sessions.set(callSid, session);

    logger.info('Session created', {
      callSid,
      sessionId: session.id,
      direction: session.direction,
      phoneNumber: session.phoneNumber,
    });

    return session;
  }

  getSession(callSid) {
    return this.sessions.get(callSid) || null;
  }

  getSessionById(sessionId) {
    for (const session of this.sessions.values()) {
      if (session.id === sessionId) {
        return session;
      }
    }
    return null;
  }

  getAllSessions() {
    return Array.from(this.sessions.values());
  }

  getActiveSessions() {
    return this.getAllSessions().filter(
      (session) => session.status !== 'ended' && session.status !== 'error'
    );
  }

  destroySession(callSid, reason = 'normal') {
    const session = this.sessions.get(callSid);
    if (!session) {
      logger.warn('Attempted to destroy non-existent session', { callSid });
      return false;
    }

    logger.info('Destroying session', {
      callSid,
      sessionId: session.id,
      reason,
      duration: Date.now() - session.createdAt.getTime(),
    });

    session.updateStatus('ended');

    if (session.twilioWs) {
      try {
        session.twilioWs.close(1000, 'Session ended');
      } catch (error) {
        logger.debug('Error closing Twilio WS', { error: error.message });
      }
      session.twilioWs = null;
    }

    if (session.openaiWs) {
      try {
        session.openaiWs.close(1000, 'Session ended');
      } catch (error) {
        logger.debug('Error closing OpenAI WS', { error: error.message });
      }
      session.openaiWs = null;
    }

    if (session.iosWs) {
      try {
        session.broadcastEvent('call.disconnected', { reason });
      } catch (error) {
        logger.debug('Error sending disconnect event', { error: error.message });
      }
    }

    const subscribers = this.eventSubscribers.get(callSid);
    if (subscribers) {
      subscribers.forEach((ws) => {
        try {
          ws.close(1000, 'Session ended');
        } catch (error) {
          logger.debug('Error closing subscriber WS', { error: error.message });
        }
      });
      this.eventSubscribers.delete(callSid);
    }

    this.sessions.delete(callSid);
    return true;
  }

  handleConnectionDrop(callSid, connectionType, error = null) {
    const session = this.sessions.get(callSid);
    if (!session) return;

    logger.warn('Connection dropped', {
      callSid,
      connectionType,
      error: error?.message,
    });

    session.broadcastEvent('connection.dropped', {
      connectionType,
      error: error?.message,
    });

    switch (connectionType) {
      case 'twilio':
        session.twilioWs = null;
        this.destroySession(callSid, 'twilio_disconnected');
        break;

      case 'openai':
        session.openaiWs = null;
        session.updateStatus('openai_disconnected');
        break;

      case 'ios':
        session.iosWs = null;
        break;
    }
  }

  registerIOSClient(deviceId, ws) {
    this.iosClients.set(deviceId, ws);
    logger.info('iOS client registered', { deviceId });
  }

  unregisterIOSClient(deviceId) {
    this.iosClients.delete(deviceId);
    logger.info('iOS client unregistered', { deviceId });
  }

  getIOSClient(deviceId) {
    return this.iosClients.get(deviceId) || null;
  }

  subscribeToEvents(callSid, ws) {
    let subscribers = this.eventSubscribers.get(callSid);
    if (!subscribers) {
      subscribers = new Set();
      this.eventSubscribers.set(callSid, subscribers);
    }
    subscribers.add(ws);
    logger.debug('Event subscriber added', { callSid, subscriberCount: subscribers.size });
  }

  unsubscribeFromEvents(callSid, ws) {
    const subscribers = this.eventSubscribers.get(callSid);
    if (subscribers) {
      subscribers.delete(ws);
      if (subscribers.size === 0) {
        this.eventSubscribers.delete(callSid);
      }
      logger.debug('Event subscriber removed', { callSid, subscriberCount: subscribers.size });
    }
  }

  broadcastEvent(callSid, eventType, data) {
    const session = this.sessions.get(callSid);
    if (session) {
      session.broadcastEvent(eventType, data);
    }

    const subscribers = this.eventSubscribers.get(callSid);
    if (subscribers) {
      const message = JSON.stringify({
        type: eventType,
        callSid,
        timestamp: new Date().toISOString(),
        data,
      });

      subscribers.forEach((ws) => {
        if (ws.readyState === 1) {
          try {
            ws.send(message);
          } catch (error) {
            logger.error('Failed to send to event subscriber', { error });
          }
        }
      });
    }
  }

  getStats() {
    const sessions = this.getAllSessions();
    return {
      totalSessions: sessions.length,
      activeSessions: this.getActiveSessions().length,
      iosClients: this.iosClients.size,
      eventSubscribers: this.eventSubscribers.size,
      sessions: sessions.map((s) => s.getStats()),
    };
  }

  cleanup() {
    logger.info('Cleaning up connection manager');

    for (const [callSid, session] of this.sessions) {
      this.destroySession(callSid, 'server_shutdown');
    }

    for (const [deviceId, ws] of this.iosClients) {
      try {
        ws.close(1001, 'Server shutdown');
      } catch (error) {
        logger.debug('Error closing iOS client', { deviceId, error: error.message });
      }
    }
    this.iosClients.clear();

    logger.info('Connection manager cleanup complete');
  }
}

const connectionManager = new ConnectionManager();

export { CallSession };
export default connectionManager;
