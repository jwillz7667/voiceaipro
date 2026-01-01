import WebSocket from 'ws';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import { pcm16Base64ToMulawBase64 } from '../audio/converter.js';
import { sendAudioToTwilio, clearTwilioBuffer } from './twilioMediaHandler.js';

const logger = createLogger('openai-realtime');

export async function connectToOpenAI(session) {
  return new Promise((resolve, reject) => {
    const url = config.openai.realtimeUrl;

    logger.info('Connecting to OpenAI Realtime API', {
      callSid: session.callSid,
      url,
    });

    const ws = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${config.openai.apiKey}`,
      },
    });

    const connectionTimeout = setTimeout(() => {
      ws.close();
      reject(new Error('OpenAI connection timeout'));
    }, 10000);

    ws.on('open', () => {
      clearTimeout(connectionTimeout);
      logger.info('OpenAI WebSocket connected', { callSid: session.callSid });
      session.setOpenAIConnection(ws);

      sendSessionConfig(session);
      resolve(ws);
    });

    ws.on('message', (data) => {
      handleOpenAIMessage(session, data);
    });

    ws.on('close', (code, reason) => {
      clearTimeout(connectionTimeout);
      logger.info('OpenAI WebSocket closed', {
        callSid: session.callSid,
        code,
        reason: reason?.toString(),
      });

      if (session.status !== 'ended') {
        session.broadcastEvent('openai.disconnected', { code, reason: reason?.toString() });
      }
    });

    ws.on('error', (error) => {
      clearTimeout(connectionTimeout);
      logger.error('OpenAI WebSocket error', {
        callSid: session.callSid,
        error: error.message,
      });
      reject(error);
    });
  });
}

function sendSessionConfig(session) {
  const sessionConfig = buildSessionConfig(session.config);

  session.sendToOpenAI({
    type: 'session.update',
    session: sessionConfig,
  });

  logger.info('Session config sent to OpenAI', {
    callSid: session.callSid,
    config: sessionConfig,
  });
}

function buildSessionConfig(config) {
  const sessionConfig = {
    modalities: ['audio', 'text'],
    instructions: config.instructions || 'You are a helpful AI assistant. Respond naturally and conversationally.',
    input_audio_format: 'pcm16',
    output_audio_format: 'pcm16',
    voice: config.voice || 'marin',
    temperature: config.temperature ?? 0.8,
    max_response_output_tokens: config.maxOutputTokens === 'inf' ? 'inf' : (config.maxOutputTokens ?? 4096),
  };

  if (config.voiceSpeed && config.voiceSpeed !== 1.0) {
    sessionConfig.output_audio_speed = config.voiceSpeed;
  }

  if (config.transcriptionModel) {
    sessionConfig.input_audio_transcription = {
      model: config.transcriptionModel,
    };
  }

  if (config.noiseReduction) {
    sessionConfig.input_audio_noise_reduction = {
      type: config.noiseReduction,
    };
  }

  if (config.vadType === 'server_vad' && config.vadConfig) {
    sessionConfig.turn_detection = {
      type: 'server_vad',
      threshold: config.vadConfig.threshold ?? 0.5,
      prefix_padding_ms: config.vadConfig.prefixPaddingMs ?? 300,
      silence_duration_ms: config.vadConfig.silenceDurationMs ?? 500,
      create_response: config.vadConfig.createResponse ?? true,
    };

    if (config.vadConfig.idleTimeoutMs) {
      sessionConfig.turn_detection.idle_timeout_ms = config.vadConfig.idleTimeoutMs;
    }
  } else if (config.vadType === 'semantic_vad' && config.vadConfig) {
    sessionConfig.turn_detection = {
      type: 'semantic_vad',
      eagerness: config.vadConfig.eagerness ?? 'auto',
      create_response: config.vadConfig.createResponse ?? true,
    };
  } else if (config.vadType === 'disabled') {
    sessionConfig.turn_detection = null;
  }

  return sessionConfig;
}

function handleOpenAIMessage(session, data) {
  try {
    const message = JSON.parse(data.toString());
    const eventType = message.type;

    session.addEvent(eventType, 'incoming', message);

    switch (eventType) {
      case 'session.created':
        logger.info('OpenAI session created', {
          callSid: session.callSid,
          sessionId: message.session?.id,
        });
        session.updateStatus('active');
        session.broadcastEvent('session.created', {
          sessionId: message.session?.id,
        });
        break;

      case 'session.updated':
        logger.info('OpenAI session updated', { callSid: session.callSid });
        session.broadcastEvent('session.updated', message.session);
        break;

      case 'input_audio_buffer.speech_started':
        logger.debug('Speech started', { callSid: session.callSid });
        session.broadcastEvent('speech.started', {
          audioStartMs: message.audio_start_ms,
        });
        break;

      case 'input_audio_buffer.speech_stopped':
        logger.debug('Speech stopped', { callSid: session.callSid });
        session.broadcastEvent('speech.stopped', {
          audioEndMs: message.audio_end_ms,
        });
        break;

      case 'input_audio_buffer.committed':
        logger.debug('Audio buffer committed', { callSid: session.callSid });
        break;

      case 'conversation.item.created':
        logger.debug('Conversation item created', {
          callSid: session.callSid,
          itemId: message.item?.id,
          role: message.item?.role,
        });
        break;

      case 'conversation.item.input_audio_transcription.completed':
        const userTranscript = message.transcript;
        if (userTranscript) {
          session.addTranscript('user', userTranscript);
          session.broadcastEvent('transcript.user', {
            text: userTranscript,
            itemId: message.item_id,
          });
          logger.info('User transcript', {
            callSid: session.callSid,
            text: userTranscript.substring(0, 100),
          });
        }
        break;

      case 'response.created':
        logger.debug('Response created', {
          callSid: session.callSid,
          responseId: message.response?.id,
        });
        session.broadcastEvent('response.started', {
          responseId: message.response?.id,
        });
        break;

      case 'response.output_item.added':
        logger.debug('Output item added', {
          callSid: session.callSid,
          itemId: message.item?.id,
        });
        break;

      case 'response.audio.delta':
      case 'response.output_audio.delta':
        const audioBase64 = message.delta;
        if (audioBase64) {
          try {
            const mulawBase64 = pcm16Base64ToMulawBase64(audioBase64);
            sendAudioToTwilio(session, mulawBase64);

            if (session.isRecording) {
              session.addRecordingChunk({
                type: 'outbound',
                audio: mulawBase64,
                timestamp: Date.now(),
              });
            }
          } catch (error) {
            logger.error('Audio conversion error (outbound)', {
              callSid: session.callSid,
              error: error.message,
            });
          }
        }
        break;

      case 'response.audio.done':
      case 'response.output_audio.done':
        logger.debug('Response audio complete', { callSid: session.callSid });
        session.broadcastEvent('response.audio.done', {});
        break;

      case 'response.audio_transcript.delta':
      case 'response.output_audio_transcript.delta':
        const transcriptDelta = message.delta;
        if (transcriptDelta) {
          session.broadcastEvent('transcript.assistant.delta', {
            text: transcriptDelta,
          });
        }
        break;

      case 'response.audio_transcript.done':
      case 'response.output_audio_transcript.done':
        const fullTranscript = message.transcript;
        if (fullTranscript) {
          session.addTranscript('assistant', fullTranscript);
          session.broadcastEvent('transcript.assistant', {
            text: fullTranscript,
          });
          logger.info('Assistant transcript', {
            callSid: session.callSid,
            text: fullTranscript.substring(0, 100),
          });
        }
        break;

      case 'response.done':
        logger.debug('Response complete', {
          callSid: session.callSid,
          responseId: message.response?.id,
          status: message.response?.status,
        });
        session.broadcastEvent('response.done', {
          responseId: message.response?.id,
          status: message.response?.status,
          usage: message.response?.usage,
        });
        break;

      case 'response.cancelled':
        logger.info('Response cancelled', { callSid: session.callSid });
        clearTwilioBuffer(session);
        session.broadcastEvent('response.cancelled', {});
        break;

      case 'rate_limits.updated':
        logger.debug('Rate limits updated', {
          callSid: session.callSid,
          rateLimits: message.rate_limits,
        });
        break;

      case 'error':
        logger.error('OpenAI error', {
          callSid: session.callSid,
          error: message.error,
        });
        session.broadcastEvent('error', {
          code: message.error?.code || 'OPENAI_ERROR',
          message: message.error?.message || 'Unknown OpenAI error',
          type: message.error?.type,
        });
        break;

      default:
        logger.trace('Unhandled OpenAI event', {
          callSid: session.callSid,
          type: eventType,
        });
    }
  } catch (error) {
    logger.error('Error processing OpenAI message', {
      callSid: session.callSid,
      error: error.message,
    });
  }
}

export function updateSessionConfig(session, newConfig) {
  session.updateConfig(newConfig);
  const sessionConfig = buildSessionConfig(session.config);

  session.sendToOpenAI({
    type: 'session.update',
    session: sessionConfig,
  });

  logger.info('Session config updated', {
    callSid: session.callSid,
    config: sessionConfig,
  });
}

export function interruptResponse(session) {
  session.sendToOpenAI({
    type: 'response.cancel',
  });

  clearTwilioBuffer(session);

  logger.info('Response interrupted', { callSid: session.callSid });
}

export function createManualResponse(session) {
  session.sendToOpenAI({
    type: 'response.create',
  });

  logger.debug('Manual response created', { callSid: session.callSid });
}

export function commitAudioBuffer(session) {
  session.sendToOpenAI({
    type: 'input_audio_buffer.commit',
  });

  logger.debug('Audio buffer committed', { callSid: session.callSid });
}

export function clearAudioBuffer(session) {
  session.sendToOpenAI({
    type: 'input_audio_buffer.clear',
  });

  logger.debug('Audio buffer cleared', { callSid: session.callSid });
}

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
    text: text.substring(0, 100),
  });
}

export default {
  connectToOpenAI,
  updateSessionConfig,
  interruptResponse,
  createManualResponse,
  commitAudioBuffer,
  clearAudioBuffer,
  sendTextMessage,
};
