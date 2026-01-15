import { verifyAccessToken, AuthError } from '../services/authService.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('middleware:auth');

/**
 * Authentication middleware
 * Verifies JWT access token and attaches user to request
 */
export function authenticate(options = {}) {
  const { required = true } = options;

  return (req, res, next) => {
    try {
      const authHeader = req.headers.authorization;

      if (!authHeader) {
        if (required) {
          return res.status(401).json({
            error: {
              code: 'MISSING_TOKEN',
              message: 'Authentication required',
            },
          });
        }
        // Optional auth - continue without user
        req.user = null;
        return next();
      }

      // Extract token from "Bearer <token>"
      const parts = authHeader.split(' ');
      if (parts.length !== 2 || parts[0] !== 'Bearer') {
        return res.status(401).json({
          error: {
            code: 'INVALID_AUTH_FORMAT',
            message: 'Authorization header must be in format: Bearer <token>',
          },
        });
      }

      const token = parts[1];

      try {
        // Verify and decode token
        const decoded = verifyAccessToken(token);

        // Attach user info to request
        req.user = {
          id: decoded.sub,
          email: decoded.email,
          name: decoded.name,
          emailVerified: decoded.emailVerified,
        };

        // Add user ID to request for logging
        req.userId = decoded.sub;

        next();
      } catch (error) {
        if (error instanceof AuthError) {
          // If auth is optional and token is expired/invalid, continue without user
          if (!required) {
            logger.debug('Optional auth failed, continuing without user', {
              code: error.code,
              message: error.message,
            });
            req.user = null;
            return next();
          }

          const statusCode = 401;
          return res.status(statusCode).json({
            error: {
              code: error.code,
              message: error.message,
            },
          });
        }
        throw error;
      }
    } catch (error) {
      logger.error('Authentication error', { error: error.message });
      res.status(500).json({
        error: {
          code: 'AUTH_ERROR',
          message: 'Authentication failed',
        },
      });
    }
  };
}

/**
 * Optional authentication middleware
 * Attaches user if token provided, but doesn't require it
 */
export function optionalAuth() {
  return authenticate({ required: false });
}

/**
 * Require verified email middleware
 * Must be used after authenticate()
 */
export function requireVerifiedEmail() {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: {
          code: 'AUTH_REQUIRED',
          message: 'Authentication required',
        },
      });
    }

    if (!req.user.emailVerified) {
      return res.status(403).json({
        error: {
          code: 'EMAIL_NOT_VERIFIED',
          message: 'Please verify your email address to access this resource',
        },
      });
    }

    next();
  };
}

/**
 * Extract device info from request
 */
export function extractDeviceInfo(req) {
  return {
    ipAddress: req.ip || req.connection?.remoteAddress,
    userAgent: req.headers['user-agent'],
    deviceId: req.headers['x-device-id'] || req.body?.device_id,
    deviceName: req.headers['x-device-name'] || req.body?.device_name,
  };
}

/**
 * Legacy device_id compatibility middleware
 * Supports both authenticated users and legacy device_id-based identification
 */
export function legacyDeviceSupport() {
  return (req, res, next) => {
    // If already authenticated, use user ID
    if (req.user) {
      return next();
    }

    // Fall back to device_id for backwards compatibility
    const deviceId = req.headers['x-device-id'] || req.query.device_id || req.body?.device_id;

    if (deviceId) {
      // Set a flag indicating legacy auth mode
      req.legacyDeviceId = deviceId;
      req.userId = null; // No authenticated user
    }

    next();
  };
}

export default {
  authenticate,
  optionalAuth,
  requireVerifiedEmail,
  extractDeviceInfo,
  legacyDeviceSupport,
};
