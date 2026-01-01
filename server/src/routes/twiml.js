import { Router } from 'express';
import twilio from 'twilio';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import { query } from '../db/pool.js';
import connectionManager from '../websocket/connectionManager.js';

const router = Router();
const logger = createLogger('routes:twiml');

const VoiceResponse = twilio.twiml.VoiceResponse;

router.post('/outgoing', (req, res) => {
  const {
    To,
    From,
    CallSid,
    userId,
    promptId,
    direction = 'outbound',
  } = req.body;

  logger.info('Outgoing call TwiML requested', {
    to: To,
    from: From,
    callSid: CallSid,
    userId,
    promptId,
  });

  const response = new VoiceResponse();

  const connect = response.connect();
  const stream = connect.stream({
    url: `wss://${req.headers.host}/media-stream`,
  });

  stream.parameter({ name: 'callSid', value: CallSid });
  stream.parameter({ name: 'direction', value: direction });
  stream.parameter({ name: 'to', value: To });
  stream.parameter({ name: 'from', value: From || config.twilio.phoneNumber });
  if (userId) {
    stream.parameter({ name: 'userId', value: userId });
  }
  if (promptId) {
    stream.parameter({ name: 'promptId', value: promptId });
  }

  res.type('text/xml');
  res.send(response.toString());

  logger.debug('Outgoing TwiML generated', { callSid: CallSid });
});

router.post('/incoming', (req, res) => {
  const {
    From,
    To,
    CallSid,
    CallerCity,
    CallerState,
    CallerCountry,
  } = req.body;

  logger.info('Incoming call TwiML requested', {
    from: From,
    to: To,
    callSid: CallSid,
    callerLocation: `${CallerCity}, ${CallerState}, ${CallerCountry}`,
  });

  const response = new VoiceResponse();

  response.say(
    { voice: 'Polly.Amy' },
    'Please hold while we connect you to our AI assistant.'
  );

  const connect = response.connect();
  const stream = connect.stream({
    url: `wss://${req.headers.host}/media-stream`,
  });

  stream.parameter({ name: 'callSid', value: CallSid });
  stream.parameter({ name: 'direction', value: 'inbound' });
  stream.parameter({ name: 'from', value: From });
  stream.parameter({ name: 'to', value: To });

  res.type('text/xml');
  res.send(response.toString());

  logger.debug('Incoming TwiML generated', { callSid: CallSid });
});

router.post('/status', async (req, res) => {
  const {
    CallSid,
    CallStatus,
    CallDuration,
    From,
    To,
    Direction,
    Timestamp,
    SipResponseCode,
    ErrorCode,
    ErrorMessage,
  } = req.body;

  logger.info('Call status callback', {
    callSid: CallSid,
    status: CallStatus,
    duration: CallDuration,
    from: From,
    to: To,
    direction: Direction,
  });

  // Map Twilio status to our internal status
  const statusMapping = {
    'initiated': 'initializing',
    'queued': 'queued',
    'ringing': 'ringing',
    'in-progress': 'active',
    'completed': 'completed',
    'busy': 'failed',
    'no-answer': 'failed',
    'canceled': 'failed',
    'failed': 'failed',
  };

  const internalStatus = statusMapping[CallStatus] || CallStatus;

  try {
    // Update call session in database
    const updates = { status: internalStatus };

    if (CallStatus === 'completed' || CallStatus === 'failed' || CallStatus === 'busy' || CallStatus === 'no-answer' || CallStatus === 'canceled') {
      updates.ended_at = new Date();
      if (CallDuration) {
        updates.duration_seconds = parseInt(CallDuration, 10);
      }
    }

    const updateParts = [];
    const params = [];
    let paramIndex = 1;

    for (const [key, value] of Object.entries(updates)) {
      updateParts.push(`${key} = $${paramIndex++}`);
      params.push(value);
    }

    params.push(CallSid);

    const result = await query(
      `UPDATE call_sessions SET ${updateParts.join(', ')}
       WHERE call_sid = $${paramIndex}
       RETURNING id, status`,
      params
    );

    if (result.rows.length > 0) {
      logger.debug('Call session updated from status callback', {
        callSid: CallSid,
        status: internalStatus,
        sessionId: result.rows[0].id,
      });

      // Log the status event
      await query(
        `INSERT INTO call_events (call_session_id, event_type, direction, payload)
         VALUES ($1, $2, 'incoming', $3)`,
        [
          result.rows[0].id,
          `status:${CallStatus}`,
          {
            callStatus: CallStatus,
            callDuration: CallDuration,
            sipResponseCode: SipResponseCode,
            errorCode: ErrorCode,
            errorMessage: ErrorMessage,
            timestamp: Timestamp,
          },
        ]
      );
    }

    // If call ended, cleanup connection manager session
    if (CallStatus === 'completed' || CallStatus === 'failed' || CallStatus === 'busy' || CallStatus === 'no-answer' || CallStatus === 'canceled') {
      connectionManager.destroySession(CallSid, `twilio_status:${CallStatus}`);
    }

  } catch (error) {
    logger.error('Failed to update call status in database', {
      callSid: CallSid,
      status: CallStatus,
      error: error.message,
    });
  }

  res.status(200).send('OK');
});

router.post('/fallback', (req, res) => {
  const { CallSid, ErrorCode, ErrorMessage } = req.body;

  logger.error('TwiML fallback triggered', {
    callSid: CallSid,
    errorCode: ErrorCode,
    errorMessage: ErrorMessage,
  });

  const response = new VoiceResponse();
  response.say(
    { voice: 'Polly.Amy' },
    'We are experiencing technical difficulties. Please try again later.'
  );
  response.hangup();

  res.type('text/xml');
  res.send(response.toString());
});

export default router;
