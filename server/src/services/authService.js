import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { query } from '../db/pool.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('services:auth');

// Configuration
const BCRYPT_ROUNDS = 12;
const ACCESS_TOKEN_EXPIRES = process.env.JWT_EXPIRES_IN || '15m';
const REFRESH_TOKEN_EXPIRES_DAYS = parseInt(process.env.REFRESH_TOKEN_EXPIRES_DAYS || '7', 10);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-production';
const PASSWORD_MIN_LENGTH = 8;
const MAX_LOGIN_ATTEMPTS = 5;
const LOGIN_LOCKOUT_MINUTES = 15;

/**
 * Hash a password using bcrypt
 */
export async function hashPassword(password) {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

/**
 * Verify a password against a hash
 */
export async function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash);
}

/**
 * Generate a secure random token
 */
export function generateSecureToken(length = 32) {
  return crypto.randomBytes(length).toString('hex');
}

/**
 * Hash a token for storage (using SHA-256)
 */
export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Generate a JWT access token
 */
export function generateAccessToken(user) {
  const payload = {
    sub: user.id,
    email: user.email,
    name: user.name,
    emailVerified: user.email_verified,
    type: 'access',
  };

  return jwt.sign(payload, JWT_SECRET, {
    expiresIn: ACCESS_TOKEN_EXPIRES,
    issuer: 'voiceai-pro',
    audience: 'voiceai-pro-api',
  });
}

/**
 * Verify and decode an access token
 */
export function verifyAccessToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET, {
      issuer: 'voiceai-pro',
      audience: 'voiceai-pro-api',
    });

    if (decoded.type !== 'access') {
      throw new Error('Invalid token type');
    }

    return decoded;
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      throw new AuthError('ACCESS_TOKEN_EXPIRED', 'Access token has expired');
    }
    if (error.name === 'JsonWebTokenError') {
      throw new AuthError('INVALID_TOKEN', 'Invalid access token');
    }
    throw error;
  }
}

/**
 * Generate a refresh token and store it in the database
 */
export async function generateRefreshToken(user, deviceInfo = {}) {
  const token = generateSecureToken(48);
  const tokenHash = hashToken(token);
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRES_DAYS * 24 * 60 * 60 * 1000);

  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device_name, device_id, ip_address, user_agent, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      user.id,
      tokenHash,
      deviceInfo.deviceName || null,
      deviceInfo.deviceId || null,
      deviceInfo.ipAddress || null,
      deviceInfo.userAgent || null,
      expiresAt,
    ]
  );

  logger.info('Refresh token created', { userId: user.id, deviceName: deviceInfo.deviceName });

  return {
    token,
    expiresAt,
  };
}

/**
 * Verify and use a refresh token (rotate on use)
 */
export async function verifyRefreshToken(token) {
  const tokenHash = hashToken(token);

  const result = await query(
    `SELECT rt.*, u.id as user_id, u.email, u.name, u.email_verified
     FROM refresh_tokens rt
     JOIN users u ON rt.user_id = u.id
     WHERE rt.token_hash = $1
       AND rt.expires_at > CURRENT_TIMESTAMP
       AND rt.revoked_at IS NULL`,
    [tokenHash]
  );

  if (result.rows.length === 0) {
    throw new AuthError('INVALID_REFRESH_TOKEN', 'Invalid or expired refresh token');
  }

  const refreshToken = result.rows[0];

  // Update last_used_at
  await query(
    'UPDATE refresh_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1',
    [refreshToken.id]
  );

  return {
    id: refreshToken.user_id,
    email: refreshToken.email,
    name: refreshToken.name,
    email_verified: refreshToken.email_verified,
    refreshTokenId: refreshToken.id,
  };
}

/**
 * Revoke a specific refresh token
 */
export async function revokeRefreshToken(tokenHash, reason = 'logout') {
  const result = await query(
    `UPDATE refresh_tokens
     SET revoked_at = CURRENT_TIMESTAMP, revoked_reason = $2
     WHERE token_hash = $1 AND revoked_at IS NULL
     RETURNING id`,
    [tokenHash, reason]
  );

  return result.rows.length > 0;
}

/**
 * Revoke all refresh tokens for a user
 */
export async function revokeAllUserTokens(userId, reason = 'logout_all') {
  const result = await query(
    `UPDATE refresh_tokens
     SET revoked_at = CURRENT_TIMESTAMP, revoked_reason = $2
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId, reason]
  );

  logger.info('All refresh tokens revoked', { userId, count: result.rowCount });
  return result.rowCount;
}

/**
 * Validate password strength
 */
export function validatePassword(password) {
  const errors = [];

  if (password.length < PASSWORD_MIN_LENGTH) {
    errors.push(`Password must be at least ${PASSWORD_MIN_LENGTH} characters`);
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }

  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one number');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Validate email format
 */
export function validateEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Check if user is locked out from login attempts
 */
export async function checkLoginLockout(email, ipAddress) {
  const windowStart = new Date(Date.now() - LOGIN_LOCKOUT_MINUTES * 60 * 1000);

  const result = await query(
    `SELECT COUNT(*) as attempts
     FROM login_attempts
     WHERE (email = $1 OR ip_address = $2)
       AND success = false
       AND created_at > $3`,
    [email.toLowerCase(), ipAddress, windowStart]
  );

  const attempts = parseInt(result.rows[0].attempts, 10);
  const isLocked = attempts >= MAX_LOGIN_ATTEMPTS;

  if (isLocked) {
    logger.warn('Login lockout active', { email, ipAddress, attempts });
  }

  return {
    isLocked,
    attempts,
    maxAttempts: MAX_LOGIN_ATTEMPTS,
    lockoutMinutes: LOGIN_LOCKOUT_MINUTES,
  };
}

/**
 * Record a login attempt
 */
export async function recordLoginAttempt(email, ipAddress, success, failureReason = null) {
  await query(
    `INSERT INTO login_attempts (email, ip_address, success, failure_reason)
     VALUES ($1, $2, $3, $4)`,
    [email.toLowerCase(), ipAddress, success, failureReason]
  );
}

/**
 * Register a new user
 */
export async function registerUser(email, password, name = null) {
  // Validate email format
  if (!validateEmail(email)) {
    throw new AuthError('INVALID_EMAIL', 'Invalid email format');
  }

  // Validate password strength
  const passwordValidation = validatePassword(password);
  if (!passwordValidation.valid) {
    throw new AuthError('WEAK_PASSWORD', passwordValidation.errors.join('. '));
  }

  // Check if email already exists
  const existing = await query(
    'SELECT id FROM users WHERE LOWER(email) = LOWER($1)',
    [email]
  );

  if (existing.rows.length > 0) {
    throw new AuthError('EMAIL_EXISTS', 'An account with this email already exists');
  }

  // Hash password
  const passwordHash = await hashPassword(password);

  // Generate email verification token
  const verificationToken = generateSecureToken();
  const verificationExpires = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

  // Create user
  const result = await query(
    `INSERT INTO users (email, password_hash, name, email_verification_token, email_verification_expires)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, email, name, email_verified, created_at`,
    [email.toLowerCase(), passwordHash, name, verificationToken, verificationExpires]
  );

  const user = result.rows[0];

  // Store password in history
  await query(
    'INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)',
    [user.id, passwordHash]
  );

  logger.info('User registered', { userId: user.id, email: user.email });

  return {
    user,
    verificationToken,
  };
}

/**
 * Login user with email and password
 */
export async function loginUser(email, password, deviceInfo = {}) {
  const ipAddress = deviceInfo.ipAddress || null;

  // Check lockout
  const lockout = await checkLoginLockout(email, ipAddress);
  if (lockout.isLocked) {
    await recordLoginAttempt(email, ipAddress, false, 'lockout');
    throw new AuthError(
      'ACCOUNT_LOCKED',
      `Too many failed login attempts. Please try again in ${lockout.lockoutMinutes} minutes.`
    );
  }

  // Find user
  const result = await query(
    `SELECT id, email, name, password_hash, email_verified, device_id
     FROM users
     WHERE LOWER(email) = LOWER($1)`,
    [email]
  );

  if (result.rows.length === 0) {
    await recordLoginAttempt(email, ipAddress, false, 'user_not_found');
    throw new AuthError('INVALID_CREDENTIALS', 'Invalid email or password');
  }

  const user = result.rows[0];

  // Verify password
  const passwordValid = await verifyPassword(password, user.password_hash);
  if (!passwordValid) {
    await recordLoginAttempt(email, ipAddress, false, 'invalid_password');
    throw new AuthError('INVALID_CREDENTIALS', 'Invalid email or password');
  }

  // Record successful login
  await recordLoginAttempt(email, ipAddress, true);

  // Update last_active
  await query(
    'UPDATE users SET last_active = CURRENT_TIMESTAMP WHERE id = $1',
    [user.id]
  );

  // Generate tokens
  const accessToken = generateAccessToken(user);
  const refreshToken = await generateRefreshToken(user, deviceInfo);

  logger.info('User logged in', { userId: user.id, email: user.email });

  return {
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
      emailVerified: user.email_verified,
    },
    accessToken,
    refreshToken: refreshToken.token,
    refreshTokenExpiresAt: refreshToken.expiresAt,
  };
}

/**
 * Verify email with token
 */
export async function verifyEmail(token) {
  const result = await query(
    `UPDATE users
     SET email_verified = true,
         email_verification_token = NULL,
         email_verification_expires = NULL
     WHERE email_verification_token = $1
       AND email_verification_expires > CURRENT_TIMESTAMP
     RETURNING id, email, name`,
    [token]
  );

  if (result.rows.length === 0) {
    throw new AuthError('INVALID_VERIFICATION_TOKEN', 'Invalid or expired verification token');
  }

  const user = result.rows[0];
  logger.info('Email verified', { userId: user.id, email: user.email });

  return user;
}

/**
 * Request password reset
 */
export async function requestPasswordReset(email) {
  const result = await query(
    'SELECT id, email FROM users WHERE LOWER(email) = LOWER($1)',
    [email]
  );

  // Don't reveal if email exists
  if (result.rows.length === 0) {
    logger.info('Password reset requested for non-existent email', { email });
    return null;
  }

  const user = result.rows[0];
  const resetToken = generateSecureToken();
  const resetExpires = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

  await query(
    `UPDATE users
     SET password_reset_token = $2, password_reset_expires = $3
     WHERE id = $1`,
    [user.id, resetToken, resetExpires]
  );

  logger.info('Password reset requested', { userId: user.id, email: user.email });

  return {
    user,
    resetToken,
  };
}

/**
 * Reset password with token
 */
export async function resetPassword(token, newPassword) {
  // Validate new password
  const passwordValidation = validatePassword(newPassword);
  if (!passwordValidation.valid) {
    throw new AuthError('WEAK_PASSWORD', passwordValidation.errors.join('. '));
  }

  // Find user with valid reset token
  const result = await query(
    `SELECT id, email FROM users
     WHERE password_reset_token = $1
       AND password_reset_expires > CURRENT_TIMESTAMP`,
    [token]
  );

  if (result.rows.length === 0) {
    throw new AuthError('INVALID_RESET_TOKEN', 'Invalid or expired reset token');
  }

  const user = result.rows[0];

  // Check password history (last 5 passwords)
  const historyResult = await query(
    `SELECT password_hash FROM password_history
     WHERE user_id = $1
     ORDER BY created_at DESC
     LIMIT 5`,
    [user.id]
  );

  for (const row of historyResult.rows) {
    const isReused = await verifyPassword(newPassword, row.password_hash);
    if (isReused) {
      throw new AuthError('PASSWORD_REUSED', 'Cannot reuse a recent password');
    }
  }

  // Hash new password
  const passwordHash = await hashPassword(newPassword);

  // Update password and clear reset token
  await query(
    `UPDATE users
     SET password_hash = $2,
         password_reset_token = NULL,
         password_reset_expires = NULL
     WHERE id = $1`,
    [user.id, passwordHash]
  );

  // Store in password history
  await query(
    'INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)',
    [user.id, passwordHash]
  );

  // Revoke all existing refresh tokens
  await revokeAllUserTokens(user.id, 'password_reset');

  logger.info('Password reset completed', { userId: user.id, email: user.email });

  return user;
}

/**
 * Get user by ID
 */
export async function getUserById(userId) {
  const result = await query(
    `SELECT id, email, name, email_verified, device_id, created_at, last_active
     FROM users
     WHERE id = $1`,
    [userId]
  );

  return result.rows[0] || null;
}

/**
 * Link device_id to authenticated user (for migrating existing data)
 */
export async function linkDeviceToUser(userId, deviceId) {
  // Check if device_id is already linked to another user
  const existing = await query(
    'SELECT id FROM users WHERE device_id = $1 AND id != $2',
    [deviceId, userId]
  );

  if (existing.rows.length > 0) {
    // Migrate data from old device-only user to authenticated user
    const oldUserId = existing.rows[0].id;

    // Update prompts
    await query(
      'UPDATE prompts SET user_id = $1 WHERE user_id = $2',
      [userId, oldUserId]
    );

    // Update call_sessions
    await query(
      'UPDATE call_sessions SET user_id = $1 WHERE user_id = $2',
      [userId, oldUserId]
    );

    // Clear device_id from old user
    await query(
      'UPDATE users SET device_id = NULL WHERE id = $1',
      [oldUserId]
    );

    logger.info('Migrated data from device user', { userId, oldUserId, deviceId });
  }

  // Link device to current user
  await query(
    'UPDATE users SET device_id = $1 WHERE id = $2',
    [deviceId, userId]
  );

  logger.info('Device linked to user', { userId, deviceId });
}

/**
 * Custom error class for authentication errors
 */
export class AuthError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AuthError';
    this.code = code;
  }
}
