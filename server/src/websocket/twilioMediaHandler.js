import { createLogger } from '../utils/logger.js';
import connectionManager from './connectionManager.js';
import { mulawBase64ToPCM16Base64 } from '../audio/converter.js';
import { connectToOpenAI } from './openaiRealtimeHandler.js';

const logger = createLogger('twilio-media');

export function handleTwilioMediaStream(ws, request) {
  let callSid = null;
  let streamSid = null;
  let session = null;
  let audioSequence = 0;

  logger.info('New Twilio Media Stream connection');

  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString());

      switch (message.event) {
        case 'connected':
          logger.info('Twilio stream connected', { protocol: message.protocol });
          break;

        case 'start':
          callSid = message.start.callSid;
          streamSid = message.start.streamSid;
          const customParameters = message.start.customParameters || {};

          logger.info('Twilio stream started', {
            callSid,
            streamSid,
            direction: customParameters.direction,
            from: customParameters.from,
          });

          session = connectionManager.getSession(callSid);
          if (!session) {
            session = connectionManager.createSession(callSid, {
              direction: customParameters.direction || 'outbound',
              phoneNumber: customParameters.to || customParameters.from || null,
              userId: customParameters.userId || null,
              promptId: customParameters.promptId || null,
            });
          }

          session.setTwilioConnection(ws, streamSid);
          session.updateStatus('connecting_openai');

          try {
            await connectToOpenAI(session);
            session.broadcastEvent('call.connected', {
              callSid,
              streamSid,
              direction: session.direction,
              phoneNumber: session.phoneNumber,
            });
          } catch (error) {
            logger.error('Failed to connect to OpenAI', { callSid, error });
            session.updateStatus('error');
            session.broadcastEvent('error', {
              code: 'E002',
              message: 'Failed to connect to OpenAI Realtime API',
              details: error.message,
            });
          }
          break;

        case 'media':
          if (!session || !session.openaiWs) {
            logger.trace('Dropping audio - OpenAI not connected', { callSid });
            break;
          }

          audioSequence++;
          const mulawBase64 = message.media.payload;

          try {
            const pcm16Base64 = mulawBase64ToPCM16Base64(mulawBase64);

            session.sendToOpenAI({
              type: 'input_audio_buffer.append',
              audio: pcm16Base64,
            });

            if (session.isRecording) {
              session.addRecordingChunk({
                type: 'inbound',
                audio: mulawBase64,
                timestamp: message.media.timestamp,
                sequence: audioSequence,
              });
            }

            if (audioSequence % 100 === 0) {
              logger.trace('Audio chunks processed', {
                callSid,
                sequence: audioSequence,
              });
            }
          } catch (error) {
            logger.error('Audio conversion error', { callSid, error: error.message });
          }
          break;

        case 'mark':
          logger.debug('Twilio mark received', {
            callSid,
            name: message.mark?.name,
          });
          session?.broadcastEvent('twilio.mark', { name: message.mark?.name });
          break;

        case 'stop':
          logger.info('Twilio stream stopped', { callSid, streamSid });
          if (session) {
            session.broadcastEvent('call.disconnected', {
              reason: 'twilio_stop',
              callSid,
            });
            connectionManager.destroySession(callSid, 'twilio_stop');
          }
          break;

        default:
          logger.debug('Unknown Twilio event', { event: message.event, callSid });
      }
    } catch (error) {
      logger.error('Error processing Twilio message', { error: error.message });
    }
  });

  ws.on('close', (code, reason) => {
    logger.info('Twilio WebSocket closed', {
      callSid,
      code,
      reason: reason?.toString(),
    });

    if (callSid) {
      connectionManager.handleConnectionDrop(callSid, 'twilio');
    }
  });

  ws.on('error', (error) => {
    logger.error('Twilio WebSocket error', { callSid, error: error.message });
    if (callSid) {
      connectionManager.handleConnectionDrop(callSid, 'twilio', error);
    }
  });
}

export function sendAudioToTwilio(session, audioBase64) {
  if (!session.streamSid) {
    logger.warn('Cannot send audio - no streamSid', { callSid: session.callSid });
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

  return session.sendToTwilio(message);
}

export function clearTwilioBuffer(session) {
  if (!session.streamSid) {
    return false;
  }

  const message = {
    event: 'clear',
    streamSid: session.streamSid,
  };

  return session.sendToTwilio(message);
}

export default {
  handleTwilioMediaStream,
  sendAudioToTwilio,
  sendMarkToTwilio,
  clearTwilioBuffer,
};
