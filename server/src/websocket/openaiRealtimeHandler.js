/**
 * OpenAI Realtime API Handler
 *
 * This module manages the WebSocket connection to OpenAI's Realtime API for
 * bidirectional speech-to-speech AI conversations.
 *
 * CONNECTION FLOW:
 * ┌─────────────┐         ┌──────────────┐         ┌─────────────────┐
 * │   Bridge    │ ──────> │   OpenAI     │ ──────> │   AI Response   │
 * │   Server    │ <────── │   Realtime   │ <────── │   Generation    │
 * └─────────────┘         └──────────────┘         └─────────────────┘
 *      │                        │
 *      │ 1. Connect (WSS)       │ 4. session.created
 *      │ 2. Auth header         │ 5. Process events
 *      │ 3. session.update      │ 6. Audio deltas
 *      ▼                        ▼
 *
 * EVENT CATEGORIES:
 * - Session: session.created, session.updated
 * - Input: input_audio_buffer.*, speech_started/stopped
 * - Transcription: conversation.item.input_audio_transcription.completed
 * - Response: response.created, response.done
 * - Audio: response.audio.delta, response.audio.done
 * - Transcript: response.audio_transcript.delta/done
 * - Error: error, rate_limits.updated
 */

import WebSocket from 'ws';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import { pcm16Base64ToMulawBase64 } from '../audio/converter.js';
import { sendAudioToTwilio, sendMarkToTwilio, clearTwilioBuffer } from './twilioMediaHandler.js';
import { logEvent } from '../services/eventLogger.js';
import { appendAIAudio } from '../services/recordingService.js';

const logger = createLogger('openai-realtime');

// Connection configuration
const CONNECTION_TIMEOUT_MS = 15000;
const MAX_RECONNECT_ATTEMPTS = 3;
const RECONNECT_DELAY_MS = 1000;

// Session state tracking per call
const sessionStates = new Map();

/**
 * Session state class to track OpenAI session status
 */
class OpenAISessionState {
  constructor(callSid) {
    this.callSid = callSid;
    this.sessionId = null;
    this.isConnected = false;
    this.isSessionReady = false;
    this.reconnectAttempts = 0;

    // Response tracking
    this.currentResponseId = null;
    this.isResponding = false;
    this.isPlayingAudio = false;

    // Transcript accumulation
    this.currentTranscriptDelta = '';

    // Statistics
    this.audioChunksSent = 0;
    this.audioChunksReceived = 0;
    this.responsesGenerated = 0;
    this.interruptionCount = 0;

    // Usage tracking
    this.totalInputTokens = 0;
    this.totalOutputTokens = 0;
    this.totalAudioInputMs = 0;
    this.totalAudioOutputMs = 0;
  }

  reset() {
    this.currentResponseId = null;
    this.isResponding = false;
    this.isPlayingAudio = false;
    this.currentTranscriptDelta = '';
  }

  getStats() {
    return {
      sessionId: this.sessionId,
      isConnected: this.isConnected,
      isSessionReady: this.isSessionReady,
      isResponding: this.isResponding,
      audioChunksSent: this.audioChunksSent,
      audioChunksReceived: this.audioChunksReceived,
      responsesGenerated: this.responsesGenerated,
      interruptionCount: this.interruptionCount,
      usage: {
        inputTokens: this.totalInputTokens,
        outputTokens: this.totalOutputTokens,
        audioInputMs: this.totalAudioInputMs,
        audioOutputMs: this.totalAudioOutputMs,
      },
    };
  }
}

/**
 * Connect to OpenAI Realtime API
 * Establishes WebSocket connection, authenticates, and configures session
 *
 * @param {Object} session - The call session from connectionManager
 * @returns {Promise<WebSocket>} - Resolves with WebSocket when session is ready
 */
export async function connectToOpenAI(session) {
  return new Promise((resolve, reject) => {
    const url = config.openai.realtimeUrl;

    logger.info('Connecting to OpenAI Realtime API', {
      callSid: session.callSid,
      url,
      model: config.openai.defaultModel,
    });

    // Initialize session state
    const state = new OpenAISessionState(session.callSid);
    sessionStates.set(session.callSid, state);

    // Create WebSocket with authorization
    const ws = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${config.openai.apiKey}`,
      },
    });

    // Connection timeout
    const connectionTimeout = setTimeout(() => {
      if (!state.isConnected) {
        ws.close();
        sessionStates.delete(session.callSid);
        reject(new Error('OpenAI connection timeout - no response within 15 seconds'));
      }
    }, CONNECTION_TIMEOUT_MS);

    // Session ready timeout (for session.created event)
    let sessionTimeout = null;

    ws.on('open', () => {
      clearTimeout(connectionTimeout);
      state.isConnected = true;

      logger.info('OpenAI WebSocket connected', {
        callSid: session.callSid,
      });

      // Store connection in session
      session.setOpenAIConnection(ws);

      // Wait for session.created before sending config
      sessionTimeout = setTimeout(() => {
        if (!state.isSessionReady) {
          logger.error('Session ready timeout', { callSid: session.callSid });
          ws.close();
          reject(new Error('OpenAI session.created timeout'));
        }
      }, CONNECTION_TIMEOUT_MS);
    });

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());

        // Handle session.created specially to resolve the promise
        if (message.type === 'session.created') {
          clearTimeout(sessionTimeout);
          state.sessionId = message.session?.id;
          state.isSessionReady = true;

          logger.info('OpenAI session created', {
            callSid: session.callSid,
            sessionId: state.sessionId,
          });

          // Now send session configuration
          sendSessionConfig(session);

          // Resolve after config is sent
          resolve(ws);
        }

        // Process all messages through handler
        handleOpenAIMessage(session, message, state);
      } catch (error) {
        logger.error('Error parsing OpenAI message', {
          callSid: session.callSid,
          error: error.message,
        });
      }
    });

    ws.on('close', (code, reason) => {
      clearTimeout(connectionTimeout);
      clearTimeout(sessionTimeout);

      const reasonStr = reason?.toString() || 'unknown';

      logger.info('OpenAI WebSocket closed', {
        callSid: session.callSid,
        code,
        reason: reasonStr,
        stats: state.getStats(),
      });

      state.isConnected = false;
      state.isSessionReady = false;

      // Broadcast disconnect event if session is still active
      if (session.status !== 'ended') {
        session.broadcastEvent('openai.disconnected', {
          code,
          reason: reasonStr,
          stats: state.getStats(),
        });

        // Attempt reconnection if unexpected close
        if (code !== 1000 && state.reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
          attemptReconnection(session, state);
        }
      }
    });

    ws.on('error', (error) => {
      clearTimeout(connectionTimeout);
      clearTimeout(sessionTimeout);

      logger.error('OpenAI WebSocket error', {
        callSid: session.callSid,
        error: error.message,
      });

      state.isConnected = false;

      if (!state.isSessionReady) {
        sessionStates.delete(session.callSid);
        reject(error);
      }
    });
  });
}

/**
 * Attempt to reconnect to OpenAI after unexpected disconnect
 */
async function attemptReconnection(session, state) {
  state.reconnectAttempts++;

  logger.info('Attempting OpenAI reconnection', {
    callSid: session.callSid,
    attempt: state.reconnectAttempts,
    maxAttempts: MAX_RECONNECT_ATTEMPTS,
  });

  // Wait before reconnecting
  await new Promise((resolve) => setTimeout(resolve, RECONNECT_DELAY_MS * state.reconnectAttempts));

  try {
    await connectToOpenAI(session);
    logger.info('OpenAI reconnection successful', {
      callSid: session.callSid,
      attempt: state.reconnectAttempts,
    });
    state.reconnectAttempts = 0;
  } catch (error) {
    logger.error('OpenAI reconnection failed', {
      callSid: session.callSid,
      attempt: state.reconnectAttempts,
      error: error.message,
    });

    session.broadcastEvent('error', {
      code: 'E002',
      message: 'Failed to reconnect to OpenAI',
      attempts: state.reconnectAttempts,
    });
  }
}

/**
 * Build and send session configuration to OpenAI
 */
function sendSessionConfig(session) {
  const sessionConfig = buildSessionConfig(session.config);

  session.sendToOpenAI({
    type: 'session.update',
    session: sessionConfig,
  });

  logger.info('Session config sent to OpenAI', {
    callSid: session.callSid,
    voice: sessionConfig.voice,
    vadType: sessionConfig.turn_detection?.type || 'disabled',
  });

  // Log to database
  logEvent(session.id, 'session.config_sent', 'outgoing', sessionConfig).catch((err) => {
    logger.error('Failed to log session config event', { error: err.message });
  });
}

/**
 * Build OpenAI session configuration from our config format
 * Maps our configuration schema to OpenAI's expected format
 */
function buildSessionConfig(cfg) {
  const sessionConfig = {
    modalities: ['audio', 'text'],
    instructions: cfg.instructions || getDefaultInstructions(),
    input_audio_format: 'pcm16',
    output_audio_format: 'pcm16',
    voice: cfg.voice || 'marin',
    temperature: cfg.temperature ?? 0.8,
    max_response_output_tokens: cfg.maxOutputTokens === 'inf' ? 'inf' : (cfg.maxOutputTokens ?? 4096),
  };

  // Voice speed (1.0 is default)
  if (cfg.voiceSpeed && cfg.voiceSpeed !== 1.0) {
    sessionConfig.output_audio_speed = cfg.voiceSpeed;
  }

  // Input audio transcription
  if (cfg.transcriptionModel) {
    sessionConfig.input_audio_transcription = {
      model: cfg.transcriptionModel,
    };
  }

  // Noise reduction
  if (cfg.noiseReduction) {
    sessionConfig.input_audio_noise_reduction = {
      type: cfg.noiseReduction,
    };
  }

  // Turn detection (VAD)
  if (cfg.vadType === 'server_vad') {
    const vadConfig = cfg.vadConfig || {};
    sessionConfig.turn_detection = {
      type: 'server_vad',
      threshold: vadConfig.threshold ?? 0.5,
      prefix_padding_ms: vadConfig.prefixPaddingMs ?? 300,
      silence_duration_ms: vadConfig.silenceDurationMs ?? 500,
      create_response: vadConfig.createResponse ?? true,
      interrupt_response: vadConfig.interruptResponse ?? true,
    };

    if (vadConfig.idleTimeoutMs) {
      sessionConfig.turn_detection.idle_timeout_ms = vadConfig.idleTimeoutMs;
    }
  } else if (cfg.vadType === 'semantic_vad') {
    const vadConfig = cfg.vadConfig || {};
    sessionConfig.turn_detection = {
      type: 'semantic_vad',
      eagerness: vadConfig.eagerness ?? 'auto',
      create_response: vadConfig.createResponse ?? true,
      interrupt_response: vadConfig.interruptResponse ?? true,
    };
  } else if (cfg.vadType === 'disabled') {
    sessionConfig.turn_detection = null;
  }

  // Tools (function calling)
  if (cfg.tools && cfg.tools.length > 0) {
    sessionConfig.tools = cfg.tools;
    sessionConfig.tool_choice = cfg.toolChoice || 'auto';
  }

  return sessionConfig;
}

/**
 * Default system instructions if none provided
 */
function getDefaultInstructions() {
  // CUSTOMIZE YOUR AI INSTRUCTIONS HERE
  return `You are a helpful AI assistant conducting a phone conversation.
Be natural, conversational, and helpful. Keep responses concise as this is a voice call.
Listen carefully and ask clarifying questions when needed.
Respond in a friendly, professional manner.

Start the conversation by greeting the caller and asking how you can help them today.`;
}

/**
 * Handle incoming messages from OpenAI Realtime API
 * Routes to specific handlers based on event type
 */
function handleOpenAIMessage(session, message, state) {
  const eventType = message.type;

  // Log event to session
  session.addEvent(eventType, 'incoming', message);

  // Route to specific handler
  switch (eventType) {
    case 'session.created':
      handleSessionCreated(session, message, state);
      break;

    case 'session.updated':
      handleSessionUpdated(session, message, state);
      break;

    case 'input_audio_buffer.speech_started':
      handleSpeechStarted(session, message, state);
      break;

    case 'input_audio_buffer.speech_stopped':
      handleSpeechStopped(session, message, state);
      break;

    case 'input_audio_buffer.committed':
      handleAudioBufferCommitted(session, message, state);
      break;

    case 'conversation.item.created':
      handleConversationItemCreated(session, message, state);
      break;

    case 'conversation.item.input_audio_transcription.completed':
      handleInputTranscription(session, message, state);
      break;

    case 'response.created':
      handleResponseCreated(session, message, state);
      break;

    case 'response.output_item.added':
      handleOutputItemAdded(session, message, state);
      break;

    case 'response.audio.delta':
    case 'response.output_audio.delta':
      handleAudioDelta(session, message, state);
      break;

    case 'response.audio.done':
    case 'response.output_audio.done':
      handleAudioDone(session, message, state);
      break;

    case 'response.audio_transcript.delta':
    case 'response.output_audio_transcript.delta':
      handleTranscriptDelta(session, message, state);
      break;

    case 'response.audio_transcript.done':
    case 'response.output_audio_transcript.done':
      handleTranscriptDone(session, message, state);
      break;

    case 'response.done':
      handleResponseDone(session, message, state);
      break;

    case 'response.cancelled':
      handleResponseCancelled(session, message, state);
      break;

    case 'rate_limits.updated':
      handleRateLimitsUpdated(session, message, state);
      break;

    case 'error':
      handleError(session, message, state);
      break;

    default:
      logger.trace('Unhandled OpenAI event', {
        callSid: session.callSid,
        type: eventType,
      });
  }
}

// =============================================================================
// EVENT HANDLERS
// =============================================================================

function handleSessionCreated(session, message, state) {
  state.sessionId = message.session?.id;
  session.updateStatus('active');

  session.broadcastEvent('session.created', {
    sessionId: state.sessionId,
    model: message.session?.model,
  });
}

function handleSessionUpdated(session, message, state) {
  logger.info('OpenAI session updated', {
    callSid: session.callSid,
    sessionId: state.sessionId,
  });

  session.broadcastEvent('session.updated', {
    session: message.session,
  });
}

/**
 * Handle speech started - user is speaking
 * CRITICAL: If AI is currently responding, we need to interrupt
 */
function handleSpeechStarted(session, message, state) {
  const audioStartMs = message.audio_start_ms;

  logger.debug('Speech started', {
    callSid: session.callSid,
    audioStartMs,
    wasResponding: state.isResponding,
    wasPlayingAudio: state.isPlayingAudio,
  });

  // INTERRUPTION: If AI is currently speaking, cancel the response
  if (state.isResponding || state.isPlayingAudio) {
    logger.info('Interrupting AI response due to user speech', {
      callSid: session.callSid,
      responseId: state.currentResponseId,
    });

    state.interruptionCount++;

    // Cancel OpenAI response
    cancelResponse(session);

    // Clear Twilio audio buffer
    clearTwilioBuffer(session);

    session.broadcastEvent('response.interrupted', {
      responseId: state.currentResponseId,
      reason: 'user_speech',
    });
  }

  session.broadcastEvent('speech.started', {
    audioStartMs,
  });
}

function handleSpeechStopped(session, message, state) {
  const audioEndMs = message.audio_end_ms;

  logger.debug('Speech stopped', {
    callSid: session.callSid,
    audioEndMs,
  });

  session.broadcastEvent('speech.stopped', {
    audioEndMs,
  });
}

function handleAudioBufferCommitted(session, message, state) {
  logger.trace('Audio buffer committed', {
    callSid: session.callSid,
    itemId: message.item_id,
  });
}

function handleConversationItemCreated(session, message, state) {
  const item = message.item;

  logger.debug('Conversation item created', {
    callSid: session.callSid,
    itemId: item?.id,
    type: item?.type,
    role: item?.role,
  });
}

/**
 * Handle completed user transcription
 */
function handleInputTranscription(session, message, state) {
  const transcript = message.transcript;
  const itemId = message.item_id;

  if (transcript) {
    // Save to session transcripts
    session.addTranscript('user', transcript);

    // Broadcast to iOS client
    session.broadcastEvent('transcript.user', {
      text: transcript,
      itemId,
    });

    logger.info('User transcript', {
      callSid: session.callSid,
      text: transcript.length > 100 ? transcript.substring(0, 100) + '...' : transcript,
    });

    // Log to database
    logEvent(session.id, 'transcript.user', 'incoming', { transcript, itemId }).catch(() => {});
  }
}

/**
 * Handle response created - AI is starting to generate
 */
function handleResponseCreated(session, message, state) {
  const responseId = message.response?.id;

  state.currentResponseId = responseId;
  state.isResponding = true;
  state.responsesGenerated++;
  state.currentTranscriptDelta = '';

  logger.debug('Response created', {
    callSid: session.callSid,
    responseId,
    responseNumber: state.responsesGenerated,
  });

  session.broadcastEvent('response.started', {
    responseId,
  });
}

function handleOutputItemAdded(session, message, state) {
  logger.trace('Output item added', {
    callSid: session.callSid,
    itemId: message.item?.id,
    type: message.item?.type,
  });
}

/**
 * Handle audio delta - AI audio chunk to forward to Twilio
 * This is the main audio output path
 */
function handleAudioDelta(session, message, state) {
  const audioBase64 = message.delta;

  if (!audioBase64) {
    return;
  }

  state.isPlayingAudio = true;
  state.audioChunksReceived++;

  // Estimate audio duration (~20ms per chunk at 24kHz)
  state.totalAudioOutputMs += 20;

  try {
    // Convert PCM16 24kHz to μ-law 8kHz for Twilio
    const mulawBase64 = pcm16Base64ToMulawBase64(audioBase64);

    // Send to Twilio
    sendAudioToTwilio(session, mulawBase64);

    // Send AI audio to recording service (PCM16 at 24kHz)
    if (session.isRecording) {
      // Decode base64 to get PCM16 samples
      const pcm16Buffer = Buffer.from(audioBase64, 'base64');
      const samples = new Int16Array(
        pcm16Buffer.buffer,
        pcm16Buffer.byteOffset,
        pcm16Buffer.length / 2
      );
      appendAIAudio(session.callSid, samples);
    }

    // Log progress periodically
    if (state.audioChunksReceived % 100 === 0) {
      logger.debug('Audio output progress', {
        callSid: session.callSid,
        chunksReceived: state.audioChunksReceived,
        totalOutputMs: state.totalAudioOutputMs,
      });
    }
  } catch (error) {
    logger.error('Audio conversion error (outbound)', {
      callSid: session.callSid,
      error: error.message,
    });
  }
}

/**
 * Handle audio complete - AI finished sending audio for this response
 */
function handleAudioDone(session, message, state) {
  state.isPlayingAudio = false;

  logger.debug('Response audio complete', {
    callSid: session.callSid,
    responseId: state.currentResponseId,
    totalChunks: state.audioChunksReceived,
  });

  // Send a mark to Twilio to know when playback finishes
  sendMarkToTwilio(session, `response_${state.currentResponseId}_done`);

  session.broadcastEvent('response.audio.done', {
    responseId: state.currentResponseId,
  });
}

/**
 * Handle transcript delta - accumulate partial transcripts
 */
function handleTranscriptDelta(session, message, state) {
  const delta = message.delta;

  if (delta) {
    state.currentTranscriptDelta += delta;

    session.broadcastEvent('transcript.assistant.delta', {
      delta,
      accumulated: state.currentTranscriptDelta,
    });
  }
}

/**
 * Handle transcript complete - save full assistant transcript
 */
function handleTranscriptDone(session, message, state) {
  const transcript = message.transcript || state.currentTranscriptDelta;

  if (transcript) {
    // Save to session transcripts
    session.addTranscript('assistant', transcript);

    // Broadcast to iOS client
    session.broadcastEvent('transcript.assistant', {
      text: transcript,
      responseId: state.currentResponseId,
    });

    logger.info('Assistant transcript', {
      callSid: session.callSid,
      text: transcript.length > 100 ? transcript.substring(0, 100) + '...' : transcript,
    });

    // Log to database
    logEvent(session.id, 'transcript.assistant', 'incoming', {
      transcript,
      responseId: state.currentResponseId,
    }).catch(() => {});
  }

  // Reset delta accumulator
  state.currentTranscriptDelta = '';
}

/**
 * Handle response complete
 */
function handleResponseDone(session, message, state) {
  const response = message.response;
  const usage = response?.usage;

  // Update usage stats
  if (usage) {
    state.totalInputTokens += usage.input_tokens || 0;
    state.totalOutputTokens += usage.output_tokens || 0;
  }

  logger.info('Response complete', {
    callSid: session.callSid,
    responseId: response?.id,
    status: response?.status,
    usage,
  });

  state.isResponding = false;
  state.isPlayingAudio = false;
  state.currentResponseId = null;

  session.broadcastEvent('response.done', {
    responseId: response?.id,
    status: response?.status,
    usage,
    stats: state.getStats(),
  });
}

/**
 * Handle response cancelled (from interruption)
 */
function handleResponseCancelled(session, message, state) {
  logger.info('Response cancelled', {
    callSid: session.callSid,
    responseId: state.currentResponseId,
  });

  state.isResponding = false;
  state.isPlayingAudio = false;

  // Clear Twilio buffer
  clearTwilioBuffer(session);

  session.broadcastEvent('response.cancelled', {
    responseId: state.currentResponseId,
  });

  state.currentResponseId = null;
}

/**
 * Handle rate limits update
 */
function handleRateLimitsUpdated(session, message, state) {
  const rateLimits = message.rate_limits;

  logger.debug('Rate limits updated', {
    callSid: session.callSid,
    rateLimits,
  });

  session.broadcastEvent('rate_limits', rateLimits);
}

/**
 * Handle error from OpenAI
 */
function handleError(session, message, state) {
  const error = message.error;

  logger.error('OpenAI error', {
    callSid: session.callSid,
    type: error?.type,
    code: error?.code,
    message: error?.message,
    param: error?.param,
  });

  session.broadcastEvent('error', {
    source: 'openai',
    code: error?.code || 'OPENAI_ERROR',
    message: error?.message || 'Unknown OpenAI error',
    type: error?.type,
    param: error?.param,
  });

  // Log to database
  logEvent(session.id, 'error', 'incoming', error).catch(() => {});
}

// =============================================================================
// PUBLIC API FUNCTIONS
// =============================================================================

/**
 * Send audio to OpenAI (input from user via Twilio)
 * Audio should be base64-encoded PCM16 24kHz
 */
export function sendAudioToOpenAI(session, pcm24kBase64) {
  const state = sessionStates.get(session.callSid);

  if (!state || !state.isSessionReady) {
    logger.trace('Dropping audio - session not ready', { callSid: session.callSid });
    return false;
  }

  state.audioChunksSent++;

  session.sendToOpenAI({
    type: 'input_audio_buffer.append',
    audio: pcm24kBase64,
  });

  return true;
}

/**
 * Commit the audio buffer (signal end of speech for manual VAD)
 */
export function commitAudioBuffer(session) {
  session.sendToOpenAI({
    type: 'input_audio_buffer.commit',
  });

  logger.debug('Audio buffer committed', { callSid: session.callSid });
}

/**
 * Clear the audio buffer (discard pending audio)
 */
export function clearAudioBuffer(session) {
  session.sendToOpenAI({
    type: 'input_audio_buffer.clear',
  });

  logger.debug('Audio buffer cleared', { callSid: session.callSid });
}

/**
 * Cancel the current response (for interruption)
 */
export function cancelResponse(session) {
  const state = sessionStates.get(session.callSid);

  session.sendToOpenAI({
    type: 'response.cancel',
  });

  if (state) {
    state.isResponding = false;
    state.isPlayingAudio = false;
  }

  logger.info('Response cancelled', { callSid: session.callSid });
}

/**
 * Alias for cancelResponse (backwards compatibility)
 */
export function interruptResponse(session) {
  cancelResponse(session);
  clearTwilioBuffer(session);
}

/**
 * Manually trigger a response (for manual VAD mode)
 */
export function createManualResponse(session, options = {}) {
  const event = {
    type: 'response.create',
  };

  if (options.instructions) {
    event.response = {
      instructions: options.instructions,
    };
  }

  session.sendToOpenAI(event);

  logger.debug('Manual response created', { callSid: session.callSid });
}

/**
 * Update session configuration mid-call
 */
export function updateSessionConfig(session, newConfig) {
  // Merge with existing config
  session.updateConfig(newConfig);

  // Build and send new config
  const sessionConfig = buildSessionConfig(session.config);

  session.sendToOpenAI({
    type: 'session.update',
    session: sessionConfig,
  });

  logger.info('Session config updated', {
    callSid: session.callSid,
    changes: Object.keys(newConfig),
  });

  session.broadcastEvent('config.updated', {
    config: session.config,
  });
}

/**
 * Send a text message to the conversation
 */
export function sendTextMessage(session, text, role = 'user') {
  session.sendToOpenAI({
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: role,
      content: [
        {
          type: 'input_text',
          text: text,
        },
      ],
    },
  });

  logger.info('Text message sent', {
    callSid: session.callSid,
    role,
    textLength: text.length,
  });

  // Trigger response after adding text
  if (role === 'user') {
    createManualResponse(session);
  }
}

/**
 * Send function call result back to OpenAI
 */
export function sendFunctionResult(session, callId, result) {
  session.sendToOpenAI({
    type: 'conversation.item.create',
    item: {
      type: 'function_call_output',
      call_id: callId,
      output: typeof result === 'string' ? result : JSON.stringify(result),
    },
  });

  logger.info('Function result sent', {
    callSid: session.callSid,
    callId,
  });

  // Trigger response to continue after function result
  createManualResponse(session);
}

/**
 * Get session state and statistics
 */
export function getSessionState(callSid) {
  const state = sessionStates.get(callSid);
  return state ? state.getStats() : null;
}

/**
 * Close OpenAI connection gracefully
 */
export function closeOpenAIConnection(session) {
  const state = sessionStates.get(session.callSid);

  if (session.openaiWs) {
    try {
      session.openaiWs.close(1000, 'Session ended');
    } catch (error) {
      logger.debug('Error closing OpenAI connection', { error: error.message });
    }
  }

  if (state) {
    logger.info('OpenAI connection closed', {
      callSid: session.callSid,
      stats: state.getStats(),
    });
    sessionStates.delete(session.callSid);
  }
}

export default {
  connectToOpenAI,
  sendAudioToOpenAI,
  commitAudioBuffer,
  clearAudioBuffer,
  cancelResponse,
  interruptResponse,
  createManualResponse,
  updateSessionConfig,
  sendTextMessage,
  sendFunctionResult,
  getSessionState,
  closeOpenAIConnection,
};
