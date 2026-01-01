import { Router } from 'express';
import twilio from 'twilio';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('routes:token');

const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

router.post('/', (req, res) => {
  try {
    const { identity, device_id } = req.body;

    if (!identity && !device_id) {
      return res.status(400).json({
        error: {
          code: 'MISSING_IDENTITY',
          message: 'Either identity or device_id is required',
        },
      });
    }

    const tokenIdentity = identity || device_id;

    const accessToken = new AccessToken(
      config.twilio.accountSid,
      config.twilio.apiKey,
      config.twilio.apiSecret,
      {
        identity: tokenIdentity,
        ttl: 3600,
      }
    );

    const voiceGrant = new VoiceGrant({
      outgoingApplicationSid: config.twilio.twimlAppSid,
      incomingAllow: true,
    });

    accessToken.addGrant(voiceGrant);

    const token = accessToken.toJwt();

    logger.info('Access token generated', {
      identity: tokenIdentity,
      expiresIn: '1 hour',
    });

    res.json({
      token,
      identity: tokenIdentity,
      expires_in: 3600,
    });
  } catch (error) {
    logger.error('Token generation failed', error);
    res.status(500).json({
      error: {
        code: 'TOKEN_GENERATION_FAILED',
        message: 'Failed to generate access token',
        details: error.message,
      },
    });
  }
});

router.post('/refresh', (req, res) => {
  try {
    const { identity } = req.body;

    if (!identity) {
      return res.status(400).json({
        error: {
          code: 'MISSING_IDENTITY',
          message: 'Identity is required for token refresh',
        },
      });
    }

    const accessToken = new AccessToken(
      config.twilio.accountSid,
      config.twilio.apiKey,
      config.twilio.apiSecret,
      {
        identity,
        ttl: 3600,
      }
    );

    const voiceGrant = new VoiceGrant({
      outgoingApplicationSid: config.twilio.twimlAppSid,
      incomingAllow: true,
    });

    accessToken.addGrant(voiceGrant);

    const token = accessToken.toJwt();

    logger.info('Access token refreshed', { identity });

    res.json({
      token,
      identity,
      expires_in: 3600,
    });
  } catch (error) {
    logger.error('Token refresh failed', error);
    res.status(500).json({
      error: {
        code: 'TOKEN_REFRESH_FAILED',
        message: 'Failed to refresh access token',
        details: error.message,
      },
    });
  }
});

export default router;
