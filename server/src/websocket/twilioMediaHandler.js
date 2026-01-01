/**
 * Twilio Media Stream Handler
 *
 * This module handles the WebSocket connection from Twilio Media Streams and bridges
 * audio between Twilio (μ-law 8kHz) and OpenAI Realtime API (PCM16 24kHz).
 *
 * AUDIO FLOW (Inbound - User speaking):
 * ┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
 * │   Phone     │───>│   Twilio     │───>│   Bridge    │───>│   OpenAI     │
 * │   (PSTN)    │    │   (μ-law)    │    │   Server    │    │   (PCM16)    │
 * └─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
 *                    ~20ms chunks        Buffer to ~100ms   24kHz mono
 *                    8kHz mono           Convert format
 *
 * AUDIO FLOW (Outbound - AI speaking):
 * ┌──────────────┐    ┌─────────────┐    ┌──────────────┐    ┌─────────────┐
 * │   OpenAI     │───>│   Bridge    │───>│   Twilio     │───>│   Phone     │
 * │   (PCM16)    │    │   Server    │    │   (μ-law)    │    │   (PSTN)    │
 * └──────────────┘    └─────────────┘    └──────────────┘    └─────────────┘
 *   24kHz mono        Convert format     8kHz mono
 *                     Downsample 3x
 */

import { createLogger } from '../utils/logger.js';
import connectionManager from './connectionManager.js';
import { mulawBase64ToPCM16Base64, AudioChunkBuffer } from '../audio/converter.js';
import { connectToOpenAI } from './openaiRealtimeHandler.js';
import { logEvent, logTranscript } from '../services/eventLogger.js';
import { processCallRecording } from '../services/recordingService.js';
import { query } from '../db/pool.js';

const logger = createLogger('twilio-media');

/**
 * Audio buffer configuration
 * Twilio sends ~20ms chunks, OpenAI expects ~100-200ms chunks
 * At 24kHz, 100ms = 2400 samples, 200ms = 4800 samples
 */
const AUDIO_BUFFER_TARGET_SAMPLES = 2400; // ~100ms at 24kHz
const AUDIO_BUFFER_FLUSH_INTERVAL_MS = 100; // Force flush every 100ms

/**
 * Session-specific audio buffer for accumulating small chunks
 * before sending to OpenAI
 */
class TwilioSessionBuffer {
  constructor(callSid) {
    this.callSid = callSid;
    this.buffer = [];
    this.totalSamples = 0;
    this.lastFlushTime = Date.now();
    this.flushTimer = null;
  }

  /**
   * Add PCM16 samples to the buffer
   * @param {Int16Array} samples - Audio samples to add
   * @returns {Int16Array|null} - Returns accumulated samples if buffer is full
   */
  add(samples) {
    this.buffer.push(samples);
    this.totalSamples += samples.length;

    // Check if we have enough samples to send
    if (this.totalSamples >= AUDIO_BUFFER_TARGET_SAMPLES) {
      return this.flush();
    }

    return null;
  }

  /**
   * Flush all buffered samples
   * @returns {Int16Array|null} - Combined samples or null if empty
   */
  flush() {
    if (this.buffer.length === 0) {
      return null;
    }

    // Combine all buffered samples into one array
    const combined = new Int16Array(this.totalSamples);
    let offset = 0;
    for (const chunk of this.buffer) {
      combined.set(chunk, offset);
      offset += chunk.length;
    }

    // Reset buffer
    this.buffer = [];
    this.totalSamples = 0;
    this.lastFlushTime = Date.now();

    return combined;
  }

  /**
   * Check if buffer should be flushed based on time
   */
  shouldFlush() {
    return this.buffer.length > 0 &&
           (Date.now() - this.lastFlushTime) >= AUDIO_BUFFER_FLUSH_INTERVAL_MS;
  }

  /**
   * Clean up resources
   */
  destroy() {
    if (this.flushTimer) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
    this.buffer = [];
    this.totalSamples = 0;
  }
}

// Map to store audio buffers per session
const sessionBuffers = new Map();

/**
 * Main handler for Twilio Media Stream WebSocket connections
 * This is called when Twilio connects via the /media-stream endpoint
 *
 * @param {WebSocket} ws - The WebSocket connection from Twilio
 * @param {Request} request - The HTTP upgrade request
 */
export function handleTwilioMediaStream(ws, request) {
  // Session state variables
  let callSid = null;
  let streamSid = null;
  let session = null;
  let protocolVersion = null;
  let audioBuffer = null;

  // Statistics tracking
  let audioSequence = 0;
  let totalAudioMs = 0;
  let callStartTime = null;

  logger.info('New Twilio Media Stream connection', {
    remoteAddress: request.socket?.remoteAddress,
  });

  // Set up periodic buffer flush timer
  const flushInterval = setInterval(() => {
    if (audioBuffer && audioBuffer.shouldFlush() && session?.openaiWs) {
      const samples = audioBuffer.flush();
      if (samples) {
        sendBufferedAudioToOpenAI(session, samples);
      }
    }
  }, AUDIO_BUFFER_FLUSH_INTERVAL_MS / 2);

  /**
   * Handle incoming WebSocket messages from Twilio
   */
  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString());

      switch (message.event) {
        case 'connected':
          handleConnected(message);
          break;

        case 'start':
          await handleStart(message);
          break;

        case 'media':
          handleMedia(message);
          break;

        case 'mark':
          handleMark(message);
          break;

        case 'stop':
          await handleStop(message);
          break;

        default:
          logger.debug('Unknown Twilio event', {
            event: message.event,
            callSid
          });
      }
    } catch (error) {
      logger.error('Error processing Twilio message', {
        error: error.message,
        callSid,
      });
    }
  });

  /**
   * Handle WebSocket close event
   */
  ws.on('close', (code, reason) => {
    logger.info('Twilio WebSocket closed', {
      callSid,
      streamSid,
      code,
      reason: reason?.toString(),
      totalAudioMs,
      audioChunksProcessed: audioSequence,
    });

    cleanup();

    if (callSid) {
      connectionManager.handleConnectionDrop(callSid, 'twilio');
    }
  });

  /**
   * Handle WebSocket error event
   */
  ws.on('error', (error) => {
    logger.error('Twilio WebSocket error', {
      callSid,
      error: error.message
    });

    cleanup();

    if (callSid) {
      connectionManager.handleConnectionDrop(callSid, 'twilio', error);
    }
  });

  /**
   * Clean up resources when connection ends
   */
  function cleanup() {
    clearInterval(flushInterval);

    if (audioBuffer) {
      audioBuffer.destroy();
      sessionBuffers.delete(callSid);
    }
  }

  /**
   * Handle 'connected' event - Twilio WebSocket has connected
   * This is the first message received, contains protocol version
   */
  function handleConnected(message) {
    protocolVersion = message.protocol;

    logger.info('Twilio stream connected', {
      protocol: protocolVersion,
    });
  }

  /**
   * Handle 'start' event - Media stream is starting
   * Extract call info, create session, connect to OpenAI
   */
  async function handleStart(message) {
    callSid = message.start.callSid;
    streamSid = message.start.streamSid;
    callStartTime = Date.now();

    const customParameters = message.start.customParameters || {};
    const mediaFormat = message.start.mediaFormat || {};

    logger.info('Twilio stream started', {
      callSid,
      streamSid,
      direction: customParameters.direction,
      from: customParameters.from,
      to: customParameters.to,
      encoding: mediaFormat.encoding,     // Expected: audio/x-mulaw
      sampleRate: mediaFormat.sampleRate, // Expected: 8000
      channels: mediaFormat.channels,     // Expected: 1
    });

    // Create or retrieve session
    session = connectionManager.getSession(callSid);
    if (!session) {
      session = connectionManager.createSession(callSid, {
        direction: customParameters.direction || 'outbound',
        phoneNumber: customParameters.to || customParameters.from || null,
        userId: customParameters.userId || null,
        promptId: customParameters.promptId || null,
        protocolVersion,
      });
    }

    // Initialize audio buffer for this session
    audioBuffer = new TwilioSessionBuffer(callSid);
    sessionBuffers.set(callSid, audioBuffer);

    // Set Twilio connection on session
    session.setTwilioConnection(ws, streamSid);
    session.updateStatus('connecting_openai');

    // Log call start event to database
    try {
      await logCallStart(session, customParameters);
    } catch (error) {
      logger.error('Failed to log call start', { callSid, error: error.message });
    }

    // Connect to OpenAI Realtime API
    try {
      await connectToOpenAI(session);

      session.broadcastEvent('call.connected', {
        callSid,
        streamSid,
        direction: session.direction,
        phoneNumber: session.phoneNumber,
        protocolVersion,
      });

      logger.info('Call fully connected', {
        callSid,
        direction: session.direction,
      });
    } catch (error) {
      logger.error('Failed to connect to OpenAI', {
        callSid,
        error: error.message
      });

      session.updateStatus('error');
      session.broadcastEvent('error', {
        code: 'E002',
        message: 'Failed to connect to OpenAI Realtime API',
        details: error.message,
      });
    }
  }

  /**
   * Handle 'media' event - Audio data from Twilio
   * Convert μ-law 8kHz to PCM16 24kHz and buffer for OpenAI
   */
  function handleMedia(message) {
    // Skip if OpenAI not connected
    if (!session || !session.openaiWs) {
      if (audioSequence === 0) {
        logger.trace('Dropping audio - OpenAI not connected', { callSid });
      }
      return;
    }

    audioSequence++;

    // Extract μ-law audio (base64 encoded)
    const mulawBase64 = message.media.payload;
    const timestamp = message.media.timestamp;
    const track = message.media.track; // 'inbound' or 'outbound'

    // Track audio duration (~20ms per Twilio chunk at 8kHz with 160 samples)
    totalAudioMs += 20;

    try {
      // Convert μ-law 8kHz to PCM16 24kHz
      // This involves: decode μ-law → resample 8kHz→24kHz
      const pcm16Base64 = mulawBase64ToPCM16Base64(mulawBase64);

      // Decode base64 to get samples for buffering
      const pcm16Buffer = Buffer.from(pcm16Base64, 'base64');
      const samples = new Int16Array(
        pcm16Buffer.buffer,
        pcm16Buffer.byteOffset,
        pcm16Buffer.length / 2
      );

      // Add to buffer - returns samples if buffer is full
      const bufferedSamples = audioBuffer.add(samples);

      if (bufferedSamples) {
        sendBufferedAudioToOpenAI(session, bufferedSamples);
      }

      // Store for recording if enabled
      if (session.isRecording) {
        session.addRecordingChunk({
          type: track || 'inbound',
          audio: mulawBase64,
          timestamp: timestamp,
          sequence: audioSequence,
        });
      }

      // Log progress periodically
      if (audioSequence % 500 === 0) {
        logger.debug('Audio processing progress', {
          callSid,
          chunksProcessed: audioSequence,
          totalDurationMs: totalAudioMs,
          bufferSamples: audioBuffer.totalSamples,
        });
      }
    } catch (error) {
      logger.error('Audio conversion error', {
        callSid,
        error: error.message,
        sequence: audioSequence,
      });
    }
  }

  /**
   * Handle 'mark' event - Playback marker for synchronization
   * Useful for tracking when audio has been played to the user
   */
  function handleMark(message) {
    const markName = message.mark?.name;

    logger.debug('Twilio playback mark received', {
      callSid,
      markName,
      timestamp: Date.now(),
    });

    if (session) {
      session.broadcastEvent('twilio.mark', {
        name: markName,
        timestamp: Date.now(),
      });
    }
  }

  /**
   * Handle 'stop' event - Media stream has ended
   * Finalize recording, calculate duration, clean up
   */
  async function handleStop(message) {
    const callEndTime = Date.now();
    const durationMs = callStartTime ? callEndTime - callStartTime : 0;
    const durationSeconds = Math.floor(durationMs / 1000);

    logger.info('Twilio stream stopped', {
      callSid,
      streamSid,
      durationSeconds,
      audioChunksProcessed: audioSequence,
      totalAudioMs,
    });

    if (!session) {
      cleanup();
      return;
    }

    // Flush any remaining audio in buffer
    if (audioBuffer) {
      const remainingSamples = audioBuffer.flush();
      if (remainingSamples && session.openaiWs) {
        sendBufferedAudioToOpenAI(session, remainingSamples);
      }
    }

    // Broadcast disconnect event
    session.broadcastEvent('call.disconnected', {
      reason: 'twilio_stop',
      callSid,
      durationSeconds,
      audioChunksProcessed: audioSequence,
    });

    // Finalize recording if enabled
    if (session.isRecording) {
      try {
        const recording = await processCallRecording(session);
        if (recording) {
          logger.info('Recording saved', {
            callSid,
            recordingId: recording.id,
            durationSeconds: recording.duration_seconds,
          });
        }
      } catch (error) {
        logger.error('Failed to save recording', {
          callSid,
          error: error.message
        });
      }
    }

    // Update database with final call status
    try {
      await logCallEnd(session, durationSeconds, 'completed');
    } catch (error) {
      logger.error('Failed to log call end', { callSid, error: error.message });
    }

    // Clean up and destroy session
    cleanup();
    connectionManager.destroySession(callSid, 'twilio_stop');
  }
}

/**
 * Send buffered PCM16 audio samples to OpenAI
 * @param {Object} session - The call session
 * @param {Int16Array} samples - Audio samples to send
 */
function sendBufferedAudioToOpenAI(session, samples) {
  if (!session.openaiWs || session.openaiWs.readyState !== 1) {
    return;
  }

  // Convert Int16Array to base64
  const buffer = Buffer.from(samples.buffer, samples.byteOffset, samples.byteLength);
  const base64Audio = buffer.toString('base64');

  session.sendToOpenAI({
    type: 'input_audio_buffer.append',
    audio: base64Audio,
  });
}

/**
 * Log call start to database
 */
async function logCallStart(session, customParameters) {
  try {
    // Insert or update call session in database
    await query(
      `INSERT INTO call_sessions (id, call_sid, direction, phone_number, status, user_id, prompt_id, config_snapshot)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (call_sid) DO UPDATE SET
         status = $5,
         config_snapshot = $8`,
      [
        session.id,
        session.callSid,
        session.direction,
        session.phoneNumber,
        'active',
        session.userId || null,
        session.promptId || null,
        JSON.stringify(session.config),
      ]
    );

    // Log event
    await logEvent(session.id, 'call.started', 'incoming', {
      direction: session.direction,
      phoneNumber: session.phoneNumber,
      customParameters,
    });
  } catch (error) {
    logger.error('Database error logging call start', {
      callSid: session.callSid,
      error: error.message
    });
  }
}

/**
 * Log call end to database
 */
async function logCallEnd(session, durationSeconds, status) {
  try {
    // Update call session with end time and duration
    await query(
      `UPDATE call_sessions
       SET status = $1, ended_at = CURRENT_TIMESTAMP, duration_seconds = $2
       WHERE call_sid = $3`,
      [status, durationSeconds, session.callSid]
    );

    // Log event
    await logEvent(session.id, 'call.ended', 'incoming', {
      durationSeconds,
      status,
      transcriptCount: session.transcripts?.length || 0,
      eventCount: session.events?.length || 0,
    });

    // Save transcripts to database
    if (session.transcripts && session.transcripts.length > 0) {
      for (const transcript of session.transcripts) {
        await logTranscript(
          session.id,
          transcript.speaker,
          transcript.content,
          transcript.timestampMs
        );
      }
    }
  } catch (error) {
    logger.error('Database error logging call end', {
      callSid: session.callSid,
      error: error.message
    });
  }
}

/**
 * Send audio to Twilio WebSocket
 * Audio should already be in μ-law 8kHz base64 format
 *
 * @param {Object} session - The call session
 * @param {string} audioBase64 - Base64 encoded μ-law audio
 * @returns {boolean} - Success status
 */
export function sendAudioToTwilio(session, audioBase64) {
  if (!session.streamSid) {
    logger.warn('Cannot send audio - no streamSid', {
      callSid: session.callSid
    });
    return false;
  }

  const message = {
    event: 'media',
    streamSid: session.streamSid,
    media: {
      payload: audioBase64,
    },
  };

  return session.sendToTwilio(message);
}

/**
 * Send a mark event to Twilio for synchronization
 * Marks are returned when audio reaches that point in playback
 *
 * @param {Object} session - The call session
 * @param {string} markName - Name/identifier for the mark
 * @returns {boolean} - Success status
 */
export function sendMarkToTwilio(session, markName) {
  if (!session.streamSid) {
    return false;
  }

  const message = {
    event: 'mark',
    streamSid: session.streamSid,
    mark: {
      name: markName,
    },
  };

  logger.debug('Sending mark to Twilio', {
    callSid: session.callSid,
    markName,
  });

  return session.sendToTwilio(message);
}

/**
 * Clear Twilio's audio playback buffer
 * Used for interruption when user starts speaking
 *
 * @param {Object} session - The call session
 * @returns {boolean} - Success status
 */
export function clearTwilioBuffer(session) {
  if (!session.streamSid) {
    return false;
  }

  const message = {
    event: 'clear',
    streamSid: session.streamSid,
  };

  logger.debug('Clearing Twilio audio buffer', {
    callSid: session.callSid,
  });

  return session.sendToTwilio(message);
}

/**
 * Get audio buffer stats for a session
 * Useful for debugging audio flow issues
 */
export function getBufferStats(callSid) {
  const buffer = sessionBuffers.get(callSid);
  if (!buffer) {
    return null;
  }

  return {
    callSid,
    bufferedChunks: buffer.buffer.length,
    totalSamples: buffer.totalSamples,
    lastFlushTime: buffer.lastFlushTime,
    timeSinceFlush: Date.now() - buffer.lastFlushTime,
  };
}

export default {
  handleTwilioMediaStream,
  sendAudioToTwilio,
  sendMarkToTwilio,
  clearTwilioBuffer,
  getBufferStats,
};
