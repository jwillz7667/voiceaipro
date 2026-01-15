import { Router } from 'express';
import { createLogger } from '../utils/logger.js';
import { authenticate, extractDeviceInfo } from '../middleware/auth.js';
import {
  registerUser,
  loginUser,
  verifyEmail,
  requestPasswordReset,
  resetPassword,
  verifyRefreshToken,
  generateAccessToken,
  revokeRefreshToken,
  revokeAllUserTokens,
  hashToken,
  getUserById,
  linkDeviceToUser,
  AuthError,
} from '../services/authService.js';

const router = Router();
const logger = createLogger('routes:auth');

/**
 * POST /api/auth/register
 * Register a new user with email and password
 */
router.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Email and password are required',
        },
      });
    }

    const { user, verificationToken } = await registerUser(email, password, name);

    // TODO: Send verification email
    // For now, log the token (in production, send via email)
    logger.info('Verification token generated', {
      userId: user.id,
      token: `${verificationToken.substring(0, 8)  }...`,
    });

    res.status(201).json({
      success: true,
      message: 'Registration successful. Please verify your email.',
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        emailVerified: false,
      },
      // Include token in dev mode for testing
      ...(process.env.NODE_ENV !== 'production' && { verificationToken }),
    });
  } catch (error) {
    if (error instanceof AuthError) {
      const statusCode = error.code === 'EMAIL_EXISTS' ? 409 : 400;
      return res.status(statusCode).json({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    logger.error('Registration failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'REGISTRATION_FAILED',
        message: 'Registration failed',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/login
 * Login with email and password
 */
router.post('/login', async (req, res) => {
  try {
    const { email, password, device_id, device_name } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Email and password are required',
        },
      });
    }

    const deviceInfo = {
      ...extractDeviceInfo(req),
      deviceId: device_id || extractDeviceInfo(req).deviceId,
      deviceName: device_name || extractDeviceInfo(req).deviceName,
    };

    const result = await loginUser(email, password, deviceInfo);

    // If device_id provided, link it to the user account
    if (device_id) {
      try {
        await linkDeviceToUser(result.user.id, device_id);
      } catch (linkError) {
        logger.warn('Failed to link device', { error: linkError.message });
        // Don't fail login if device linking fails
      }
    }

    res.json({
      success: true,
      user: result.user,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresAt: result.refreshTokenExpiresAt,
    });
  } catch (error) {
    if (error instanceof AuthError) {
      const statusCode = error.code === 'ACCOUNT_LOCKED' ? 429 : 401;
      return res.status(statusCode).json({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    logger.error('Login failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'LOGIN_FAILED',
        message: 'Login failed',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/logout
 * Logout and invalidate refresh token
 */
router.post('/logout', async (req, res) => {
  try {
    const { refresh_token, logout_all } = req.body;

    if (logout_all && req.user) {
      // Revoke all tokens for user
      await revokeAllUserTokens(req.user.id, 'logout_all');
      return res.json({
        success: true,
        message: 'All sessions logged out',
      });
    }

    if (refresh_token) {
      const tokenHash = hashToken(refresh_token);
      await revokeRefreshToken(tokenHash, 'logout');
    }

    res.json({
      success: true,
      message: 'Logged out successfully',
    });
  } catch (error) {
    logger.error('Logout failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'LOGOUT_FAILED',
        message: 'Logout failed',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/refresh
 * Exchange refresh token for new access token
 */
router.post('/refresh', async (req, res) => {
  try {
    const { refresh_token } = req.body;

    if (!refresh_token) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Refresh token is required',
        },
      });
    }

    // Verify refresh token and get user
    const user = await verifyRefreshToken(refresh_token);

    // Generate new access token
    const accessToken = generateAccessToken(user);

    res.json({
      success: true,
      accessToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        emailVerified: user.email_verified,
      },
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return res.status(401).json({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    logger.error('Token refresh failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'REFRESH_FAILED',
        message: 'Token refresh failed',
        details: error.message,
      },
    });
  }
});

/**
 * GET /api/auth/verify-email/:token
 * Verify email address with token
 */
router.get('/verify-email/:token', async (req, res) => {
  try {
    const { token } = req.params;

    const user = await verifyEmail(token);

    res.json({
      success: true,
      message: 'Email verified successfully',
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
      },
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return res.status(400).json({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    logger.error('Email verification failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'VERIFICATION_FAILED',
        message: 'Email verification failed',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/forgot-password
 * Request password reset email
 */
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Email is required',
        },
      });
    }

    const result = await requestPasswordReset(email);

    // Always return success to prevent email enumeration
    // In production, send email if user exists

    if (result) {
      // TODO: Send password reset email
      logger.info('Password reset token generated', {
        userId: result.user.id,
        token: `${result.resetToken.substring(0, 8)  }...`,
      });

      // Include token in dev mode for testing
      if (process.env.NODE_ENV !== 'production') {
        return res.json({
          success: true,
          message: 'Password reset email sent',
          resetToken: result.resetToken,
        });
      }
    }

    res.json({
      success: true,
      message: 'If an account with that email exists, a password reset link has been sent.',
    });
  } catch (error) {
    logger.error('Password reset request failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'RESET_REQUEST_FAILED',
        message: 'Password reset request failed',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/reset-password
 * Reset password with token
 */
router.post('/reset-password', async (req, res) => {
  try {
    const { token, password } = req.body;

    if (!token || !password) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Token and new password are required',
        },
      });
    }

    const user = await resetPassword(token, password);

    res.json({
      success: true,
      message: 'Password reset successful. Please login with your new password.',
      user: {
        id: user.id,
        email: user.email,
      },
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return res.status(400).json({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    logger.error('Password reset failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'RESET_FAILED',
        message: 'Password reset failed',
        details: error.message,
      },
    });
  }
});

/**
 * GET /api/auth/me
 * Get current authenticated user
 */
router.get('/me', authenticate(), async (req, res) => {
  try {
    const user = await getUserById(req.user.id);

    if (!user) {
      return res.status(404).json({
        error: {
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        },
      });
    }

    res.json({
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        emailVerified: user.email_verified,
        deviceId: user.device_id,
        createdAt: user.created_at,
        lastActive: user.last_active,
      },
    });
  } catch (error) {
    logger.error('Failed to get user', { error: error.message });
    res.status(500).json({
      error: {
        code: 'GET_USER_FAILED',
        message: 'Failed to get user information',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/link-device
 * Link a device_id to the authenticated user (for data migration)
 */
router.post('/link-device', authenticate(), async (req, res) => {
  try {
    const { device_id } = req.body;

    if (!device_id) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'device_id is required',
        },
      });
    }

    await linkDeviceToUser(req.user.id, device_id);

    res.json({
      success: true,
      message: 'Device linked successfully',
    });
  } catch (error) {
    logger.error('Failed to link device', { error: error.message });
    res.status(500).json({
      error: {
        code: 'LINK_DEVICE_FAILED',
        message: 'Failed to link device',
        details: error.message,
      },
    });
  }
});

/**
 * POST /api/auth/change-password
 * Change password for authenticated user
 */
router.post('/change-password', authenticate(), async (req, res) => {
  try {
    const { current_password, new_password } = req.body;

    if (!current_password || !new_password) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Current password and new password are required',
        },
      });
    }

    // Import functions we need
    const { verifyPassword, validatePassword, hashPassword } = await import('../services/authService.js');
    const { query } = await import('../db/pool.js');

    // Get user with password hash
    const userResult = await query(
      'SELECT id, password_hash FROM users WHERE id = $1',
      [req.user.id]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        },
      });
    }

    const user = userResult.rows[0];

    // Verify current password
    const isValid = await verifyPassword(current_password, user.password_hash);
    if (!isValid) {
      return res.status(401).json({
        error: {
          code: 'INVALID_PASSWORD',
          message: 'Current password is incorrect',
        },
      });
    }

    // Validate new password
    const validation = validatePassword(new_password);
    if (!validation.valid) {
      return res.status(400).json({
        error: {
          code: 'WEAK_PASSWORD',
          message: validation.errors.join('. '),
        },
      });
    }

    // Check password history
    const historyResult = await query(
      `SELECT password_hash FROM password_history
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 5`,
      [user.id]
    );

    for (const row of historyResult.rows) {
      const isReused = await verifyPassword(new_password, row.password_hash);
      if (isReused) {
        return res.status(400).json({
          error: {
            code: 'PASSWORD_REUSED',
            message: 'Cannot reuse a recent password',
          },
        });
      }
    }

    // Hash and save new password
    const passwordHash = await hashPassword(new_password);

    await query(
      'UPDATE users SET password_hash = $2 WHERE id = $1',
      [user.id, passwordHash]
    );

    await query(
      'INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)',
      [user.id, passwordHash]
    );

    // Optionally revoke all other sessions
    // await revokeAllUserTokens(user.id, 'password_change');

    res.json({
      success: true,
      message: 'Password changed successfully',
    });
  } catch (error) {
    logger.error('Password change failed', { error: error.message });
    res.status(500).json({
      error: {
        code: 'CHANGE_PASSWORD_FAILED',
        message: 'Failed to change password',
        details: error.message,
      },
    });
  }
});

export default router;
