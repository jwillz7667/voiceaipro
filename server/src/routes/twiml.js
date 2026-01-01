import { Router } from 'express';
import twilio from 'twilio';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';

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

router.post('/status', (req, res) => {
  const {
    CallSid,
    CallStatus,
    CallDuration,
    From,
    To,
    Direction,
  } = req.body;

  logger.info('Call status callback', {
    callSid: CallSid,
    status: CallStatus,
    duration: CallDuration,
    from: From,
    to: To,
    direction: Direction,
  });

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
