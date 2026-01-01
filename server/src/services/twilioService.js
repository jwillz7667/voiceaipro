import twilio from 'twilio';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import connectionManager from '../websocket/connectionManager.js';

const logger = createLogger('twilio-service');

const twilioClient = twilio(config.twilio.accountSid, config.twilio.authToken);

export async function initiateOutgoingCall(options) {
  const {
    to,
    from,
    userId,
    promptId,
    sessionConfig,
    statusCallback,
  } = options;

  logger.info('Initiating outgoing call via Twilio', {
    to,
    from,
    userId,
    promptId,
  });

  const twimlParams = new URLSearchParams();
  if (userId) twimlParams.set('userId', userId);
  if (promptId) twimlParams.set('promptId', promptId);
  twimlParams.set('direction', 'outbound');

  const baseUrl = process.env.SERVER_URL || `https://${process.env.RAILWAY_PUBLIC_DOMAIN || 'localhost:3000'}`;

  const call = await twilioClient.calls.create({
    to,
    from,
    url: `${baseUrl}/twiml/outgoing?${twimlParams.toString()}`,
    statusCallback: statusCallback || `${baseUrl}/twiml/status`,
    statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
    statusCallbackMethod: 'POST',
    record: false,
  });

  logger.info('Outgoing call created', {
    callSid: call.sid,
    to: call.to,
    from: call.from,
    status: call.status,
  });

  connectionManager.createSession(call.sid, {
    direction: 'outbound',
    phoneNumber: to,
    userId,
    promptId,
    config: sessionConfig,
  });

  return call;
}

export async function endCall(callSid, reason = 'completed') {
  logger.info('Ending call via Twilio', { callSid, reason });

  try {
    const call = await twilioClient.calls(callSid).update({
      status: 'completed',
    });

    logger.info('Call ended via Twilio', {
      callSid: call.sid,
      status: call.status,
      duration: call.duration,
    });

    return call;
  } catch (error) {
    if (error.code === 20404) {
      logger.warn('Call not found in Twilio - may already be ended', { callSid });
      return null;
    }
    throw error;
  }
}

export async function getCallDetails(callSid) {
  logger.debug('Fetching call details from Twilio', { callSid });

  const call = await twilioClient.calls(callSid).fetch();

  return {
    sid: call.sid,
    to: call.to,
    from: call.from,
    status: call.status,
    direction: call.direction,
    duration: call.duration,
    startTime: call.startTime,
    endTime: call.endTime,
    answeredBy: call.answeredBy,
    callerName: call.callerName,
    parentCallSid: call.parentCallSid,
    price: call.price,
    priceUnit: call.priceUnit,
  };
}

export async function updateCall(callSid, options) {
  logger.info('Updating call via Twilio', { callSid, options });

  const call = await twilioClient.calls(callSid).update(options);

  return call;
}

export async function muteCall(callSid, mute = true) {
  logger.info(`${mute ? 'Muting' : 'Unmuting'} call`, { callSid });

  return updateCall(callSid, { muted: mute });
}

export async function holdCall(callSid, hold = true) {
  logger.info(`${hold ? 'Putting' : 'Taking'} call ${hold ? 'on' : 'off'} hold`, { callSid });

  return updateCall(callSid, {
    status: hold ? 'paused' : 'in-progress',
  });
}

export async function sendDigits(callSid, digits) {
  logger.info('Sending DTMF digits', { callSid, digits: digits.replace(/\d/g, '*') });

  return updateCall(callSid, { sendDigits: digits });
}

export async function transferCall(callSid, transferTo, options = {}) {
  logger.info('Transferring call', { callSid, transferTo });

  const baseUrl = process.env.SERVER_URL || `https://${process.env.RAILWAY_PUBLIC_DOMAIN || 'localhost:3000'}`;

  const twiml = `
    <Response>
      <Dial>${transferTo}</Dial>
    </Response>
  `.trim();

  return updateCall(callSid, {
    twiml,
    ...options,
  });
}

export async function getAccountInfo() {
  const account = await twilioClient.api.accounts(config.twilio.accountSid).fetch();

  return {
    sid: account.sid,
    friendlyName: account.friendlyName,
    status: account.status,
    type: account.type,
    dateCreated: account.dateCreated,
    dateUpdated: account.dateUpdated,
  };
}

export async function getUsage(category = 'calls', startDate, endDate) {
  const today = new Date();
  const defaultStart = new Date(today.getFullYear(), today.getMonth(), 1);

  const records = await twilioClient.usage.records.list({
    category,
    startDate: startDate || defaultStart,
    endDate: endDate || today,
  });

  return records.map((record) => ({
    category: record.category,
    description: record.description,
    count: record.count,
    usage: record.usage,
    usageUnit: record.usageUnit,
    price: record.price,
    priceUnit: record.priceUnit,
    startDate: record.startDate,
    endDate: record.endDate,
  }));
}

export function validatePhoneNumber(phoneNumber) {
  const e164Regex = /^\+[1-9]\d{1,14}$/;

  if (!e164Regex.test(phoneNumber)) {
    return {
      valid: false,
      error: 'Phone number must be in E.164 format (e.g., +14155551234)',
    };
  }

  return { valid: true };
}

export async function lookupPhoneNumber(phoneNumber) {
  try {
    const lookup = await twilioClient.lookups.v2.phoneNumbers(phoneNumber).fetch({
      fields: 'line_type_intelligence',
    });

    return {
      phoneNumber: lookup.phoneNumber,
      nationalFormat: lookup.nationalFormat,
      countryCode: lookup.countryCode,
      valid: lookup.valid,
      callerName: lookup.callerName,
      lineType: lookup.lineTypeIntelligence?.type,
      carrier: lookup.lineTypeIntelligence?.carrier_name,
    };
  } catch (error) {
    logger.error('Phone number lookup failed', { phoneNumber, error: error.message });
    throw error;
  }
}

export default {
  initiateOutgoingCall,
  endCall,
  getCallDetails,
  updateCall,
  muteCall,
  holdCall,
  sendDigits,
  transferCall,
  getAccountInfo,
  getUsage,
  validatePhoneNumber,
  lookupPhoneNumber,
};
