import { v4 as uuidv4 } from 'uuid';
import { createLogger } from '../utils/logger.js';
import { query } from '../db/pool.js';
import { logTranscript } from '../services/eventLogger.js';

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

    // Event stream subscribers for this session
    this.eventSubscribers = new Set();

    // Session configuration - aligned with OpenAI Realtime API
    // See: https://platform.openai.com/docs/api-reference/realtime-client-events/session/update
    this.config = {
      // Model: gpt-realtime-1.5, gpt-realtime-1.5-mini
      model: 'gpt-realtime-1.5',
      // Voices: marin and cedar are recommended; also available: alloy, echo, shimmer, ash, ballad, coral, sage, verse
      voice: 'marin',
      voiceSpeed: 1.0,
      // VAD: semantic_vad (understands utterances), server_vad (silence-based), or disabled/none
      vadType: 'semantic_vad',
      vadConfig: {
        eagerness: 'high', // low, medium, high, auto
        createResponse: true,
        interruptResponse: true,
      },
      // Noise reduction: null, 'near_field' (headphones), 'far_field' (speakerphone)
      noiseReduction: null,
      // Transcription model for user speech: gpt-4o-transcribe, gpt-4o-mini-transcribe, or whisper-1
      transcriptionModel: 'gpt-4o-transcribe',
      // NOTE: temperature removed (not configurable)
      // NOTE: maxOutputTokens not supported in session.update
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
    logger.info('🔵 [BROADCAST] ========== BROADCAST EVENT ==========', {
      eventType,
      callSid: this.callSid,
      hasIosWs: !!this.iosWs,
      iosWsState: this.iosWs?.readyState,
      sessionSubscriberCount: this.eventSubscribers.size,
    });

    const event = this.addEvent(eventType, 'outgoing', data);
    const message = JSON.stringify({
      type: eventType,
      callSid: this.callSid,
      timestamp: event.timestamp.toISOString(),
      data,
    });

    logger.info('🔵 [BROADCAST] Message built', { messageLength: message.length });

    let sentCount = 0;

    // Send to iOS control channel
    if (this.iosWs && this.iosWs.readyState === 1) {
      try {
        this.iosWs.send(message);
        sentCount++;
        logger.info('🔵 [BROADCAST] ✅ Sent to iOS control channel');
      } catch (error) {
        logger.error('🔵 [BROADCAST] ❌ Failed to send to iOS client', { callSid: this.callSid, error });
      }
    }

    // Send to all event stream subscribers on this session
    this.eventSubscribers.forEach((ws, _index) => {
      if (ws.readyState === 1) {
        try {
          ws.send(message);
          sentCount++;
          logger.info('🔵 [BROADCAST] ✅ Sent to session subscriber');
        } catch (error) {
          logger.error('🔵 [BROADCAST] ❌ Failed to send to session subscriber', { callSid: this.callSid, error });
        }
      } else {
        logger.warn('🔵 [BROADCAST] Session subscriber not ready', { readyState: ws.readyState });
      }
    });

    // Also check connectionManager's pending subscribers (fallback for race conditions)
    const pendingSubscribers = connectionManager?.eventSubscribers?.get(this.callSid);
    if (pendingSubscribers) {
      logger.info('🔵 [BROADCAST] Found pending subscribers', { count: pendingSubscribers.size });
      pendingSubscribers.forEach((ws) => {
        if (ws.readyState === 1 && !this.eventSubscribers.has(ws)) {
          try {
            ws.send(message);
            sentCount++;
            logger.info('🔵 [BROADCAST] ✅ Sent to pending subscriber');
          } catch (error) {
            logger.error('🔵 [BROADCAST] ❌ Failed to send to pending subscriber', { callSid: this.callSid, error });
          }
        }
      });
    }

    logger.info('🔵 [BROADCAST] Complete', { totalSent: sentCount, eventType });
    return event;
  }

  addEventSubscriber(ws) {
    this.eventSubscribers.add(ws);
    logger.debug('Event subscriber added to session', { callSid: this.callSid, count: this.eventSubscribers.size });
  }

  removeEventSubscriber(ws) {
    this.eventSubscribers.delete(ws);
    logger.debug('Event subscriber removed from session', { callSid: this.callSid, count: this.eventSubscribers.size });
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
    // Pending configs for outbound calls (stored before callSid is known)
    // Key: configId (short UUID), Value: { config, createdAt }
    this.pendingConfigs = new Map();
    // Map iOS session UUIDs to Twilio callSid for correlation
    // Key: iOS session UUID, Value: callSid (Twilio)
    this.iosSessionMap = new Map();
  }

  /**
   * Store a config temporarily before a call is initiated
   * Returns a short ID that can be passed in URL params (avoids 4000 char limit)
   */
  storePendingConfig(config) {
    const configId = uuidv4().substring(0, 8); // Short 8-char ID
    this.pendingConfigs.set(configId, {
      config,
      createdAt: Date.now(),
    });
    logger.debug('Stored pending config', { configId, instructionsLength: config?.instructions?.length || 0 });

    // Clean up old pending configs after 5 minutes
    setTimeout(() => {
      if (this.pendingConfigs.has(configId)) {
        this.pendingConfigs.delete(configId);
        logger.debug('Cleaned up expired pending config', { configId });
      }
    }, 5 * 60 * 1000);

    return configId;
  }

  /**
   * Retrieve and consume a pending config by ID
   */
  getPendingConfig(configId) {
    const pending = this.pendingConfigs.get(configId);
    if (pending) {
      this.pendingConfigs.delete(configId);
      logger.debug('Retrieved pending config', { configId, age: Date.now() - pending.createdAt });
      return pending.config;
    }
    logger.warn('Pending config not found', { configId });
    return null;
  }

  createSession(callSid, options = {}) {
    if (this.sessions.has(callSid)) {
      // Session already exists - update config if provided (handles race condition)
      // This can happen when twilioMediaHandler creates session before twilioService returns
      const existingSession = this.sessions.get(callSid);
      if (options.config) {
        logger.info('Session already exists, updating config', {
          callSid,
          existingInstructions: existingSession.config.instructions?.length || 0,
          newInstructions: options.config.instructions?.length || 0,
        });
        existingSession.updateConfig(options.config);
      } else {
        logger.warn('Session already exists, returning existing', { callSid });
      }
      // Store iOS session ID mapping if provided
      if (options.iosSessionId) {
        this.iosSessionMap.set(options.iosSessionId, callSid);
        logger.info('iOS session ID mapped', { iosSessionId: options.iosSessionId, callSid });
      }
      return existingSession;
    }

    const session = new CallSession(callSid, options);
    this.sessions.set(callSid, session);

    // Store iOS session ID mapping if provided (for event stream correlation)
    if (options.iosSessionId) {
      this.iosSessionMap.set(options.iosSessionId, callSid);
      logger.info('iOS session ID mapped', { iosSessionId: options.iosSessionId, callSid });
    }

    // Transfer any pending event subscribers that connected before session was created
    const pendingSubscribers = this.eventSubscribers.get(callSid);
    if (pendingSubscribers && pendingSubscribers.size > 0) {
      logger.info('Transferring pending event subscribers to session', {
        callSid,
        count: pendingSubscribers.size,
      });
      pendingSubscribers.forEach((ws) => {
        if (ws.readyState === 1) {
          session.addEventSubscriber(ws);
        }
      });
      // Clear from pending since they're now on the session
      this.eventSubscribers.delete(callSid);
    }

    // Also check if there are pending subscribers registered with iOS session ID
    if (options.iosSessionId) {
      const iosSubscribers = this.eventSubscribers.get(options.iosSessionId);
      if (iosSubscribers && iosSubscribers.size > 0) {
        logger.info('Transferring iOS session subscribers to session', {
          callSid,
          iosSessionId: options.iosSessionId,
          count: iosSubscribers.size,
        });
        iosSubscribers.forEach((ws) => {
          if (ws.readyState === 1) {
            session.addEventSubscriber(ws);
          }
        });
        this.eventSubscribers.delete(options.iosSessionId);
      }
    }

    logger.info('Session created', {
      callSid,
      sessionId: session.id,
      iosSessionId: options.iosSessionId || null,
      direction: session.direction,
      phoneNumber: session.phoneNumber,
      config: {
        voice: session.config.voice,
        model: session.config.model,
        vadType: session.config.vadType,
        vadConfig: session.config.vadConfig,
        voiceSpeed: session.config.voiceSpeed,
        transcriptionModel: session.config.transcriptionModel,
        instructionsLength: session.config.instructions?.length || 0,
        instructionsPreview: session.config.instructions?.substring(0, 50) || '(default)',
      },
    });

    return session;
  }

  getSession(callSid) {
    return this.sessions.get(callSid) || null;
  }

  getSessionById(sessionId) {
    // First check if this is an iOS session ID that maps to a callSid
    const mappedCallSid = this.iosSessionMap.get(sessionId);
    if (mappedCallSid) {
      const session = this.sessions.get(mappedCallSid);
      if (session) {
        logger.debug('Found session via iOS session map', { sessionId, callSid: mappedCallSid });
        return session;
      }
    }

    // Otherwise search by server-generated session ID
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

    const durationMs = Date.now() - session.createdAt.getTime();
    const durationSeconds = Math.floor(durationMs / 1000);

    logger.info('Destroying session', {
      callSid,
      sessionId: session.id,
      reason,
      duration: durationMs,
      transcriptCount: session.transcripts?.length || 0,
    });

    session.updateStatus('ended');

    // Save session data to database asynchronously
    this._saveSessionToDatabase(session, durationSeconds, reason).catch(error => {
      logger.error('Failed to save session to database', { callSid, error: error.message });
    });

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

    // Clean up iOS session ID mapping
    for (const [iosSessionId, mappedCallSid] of this.iosSessionMap.entries()) {
      if (mappedCallSid === callSid) {
        this.iosSessionMap.delete(iosSessionId);
        logger.debug('Removed iOS session ID mapping', { iosSessionId, callSid });
        break;
      }
    }

    this.sessions.delete(callSid);
    return true;
  }

  /**
   * Save session data (including transcripts) to database
   */
  async _saveSessionToDatabase(session, durationSeconds, _reason) {
    try {
      // Update call session status in database
      await query(
        `UPDATE call_sessions
         SET status = 'completed', ended_at = NOW(), duration_seconds = $1
         WHERE call_sid = $2`,
        [durationSeconds, session.callSid]
      );

      logger.info('Updated call session in database', {
        callSid: session.callSid,
        durationSeconds,
      });

      // Save transcripts to database
      if (session.transcripts && session.transcripts.length > 0) {
        logger.info('Saving transcripts to database', {
          callSid: session.callSid,
          count: session.transcripts.length,
        });

        for (const transcript of session.transcripts) {
          await logTranscript(
            session.id,
            transcript.speaker,
            transcript.content,
            transcript.timestampMs,
            { callSid: session.callSid }
          );
        }

        logger.info('Transcripts saved successfully', {
          callSid: session.callSid,
          count: session.transcripts.length,
        });
      }
    } catch (error) {
      logger.error('Error saving session to database', {
        callSid: session.callSid,
        error: error.message,
        stack: error.stack,
      });
      throw error;
    }
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

    for (const [callSid, _session] of this.sessions) {
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
