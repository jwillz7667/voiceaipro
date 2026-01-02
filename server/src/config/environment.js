import 'dotenv/config';

class EnvironmentError extends Error {
  constructor(message) {
    super(message);
    this.name = 'EnvironmentError';
  }
}

function requireEnv(name, defaultValue = undefined) {
  const value = process.env[name] ?? defaultValue;
  if (value === undefined) {
    throw new EnvironmentError(`Missing required environment variable: ${name}`);
  }
  return value;
}

function requireEnvInt(name, defaultValue = undefined) {
  const value = requireEnv(name, defaultValue?.toString());
  const parsed = parseInt(value, 10);
  if (isNaN(parsed)) {
    throw new EnvironmentError(`Environment variable ${name} must be a valid integer, got: ${value}`);
  }
  return parsed;
}

function requireEnvBool(name, defaultValue = undefined) {
  const value = requireEnv(name, defaultValue?.toString());
  if (value === 'true' || value === '1') return true;
  if (value === 'false' || value === '0') return false;
  throw new EnvironmentError(`Environment variable ${name} must be 'true' or 'false', got: ${value}`);
}

const config = {
  nodeEnv: requireEnv('NODE_ENV', 'development'),
  port: requireEnvInt('PORT', 3000),

  twilio: {
    accountSid: requireEnv('TWILIO_ACCOUNT_SID'),
    authToken: requireEnv('TWILIO_AUTH_TOKEN'),
    apiKey: process.env.TWILIO_API_KEY || null,           // Optional: needed for iOS SDK tokens
    apiSecret: process.env.TWILIO_API_SECRET || null,     // Optional: needed for iOS SDK tokens
    twimlAppSid: process.env.TWIML_APP_SID || null,       // Optional: needed for iOS SDK tokens
    phoneNumber: requireEnv('TWILIO_PHONE_NUMBER'),
  },

  openai: {
    apiKey: requireEnv('OPENAI_API_KEY'),
    // Base URL - voice and turn_detection will be added dynamically per session
    realtimeBaseUrl: 'wss://api.openai.com/v1/realtime',
    defaultModel: 'gpt-realtime',
    defaultVoice: 'marin',
    defaultVadType: 'semantic_vad',
  },

  database: {
    url: requireEnv('DATABASE_URL'),
    poolMin: requireEnvInt('DB_POOL_MIN', 2),
    poolMax: requireEnvInt('DB_POOL_MAX', 10),
    idleTimeoutMs: requireEnvInt('DB_IDLE_TIMEOUT_MS', 30000),
    connectionTimeoutMs: requireEnvInt('DB_CONNECTION_TIMEOUT_MS', 5000),
  },

  recording: {
    storagePath: requireEnv('RECORDING_STORAGE_PATH', './data/recordings'),
    enabled: requireEnvBool('RECORDING_ENABLED', true),
    format: requireEnv('RECORDING_FORMAT', 'wav'),
  },

  server: {
    corsOrigins: requireEnv('CORS_ORIGINS', '*').split(',').map(s => s.trim()),
    rateLimitWindowMs: requireEnvInt('RATE_LIMIT_WINDOW_MS', 60000),
    rateLimitMax: requireEnvInt('RATE_LIMIT_MAX', 100),
    // Default to true in production (Railway, etc. use proxies)
    trustProxy: process.env.TRUST_PROXY !== undefined
      ? requireEnvBool('TRUST_PROXY', true)
      : process.env.NODE_ENV === 'production',
  },

  logging: {
    level: requireEnv('LOG_LEVEL', 'info'),
    prettyPrint: requireEnvBool('LOG_PRETTY', false),
  },

  isProduction() {
    return this.nodeEnv === 'production';
  },

  isDevelopment() {
    return this.nodeEnv === 'development';
  },

  isTest() {
    return this.nodeEnv === 'test';
  },
};

export function validateEnvironment() {
  const requiredVars = [
    'TWILIO_ACCOUNT_SID',
    'TWILIO_AUTH_TOKEN',
    'TWILIO_PHONE_NUMBER',
    'OPENAI_API_KEY',
    'DATABASE_URL',
  ];

  const missing = requiredVars.filter(name => !process.env[name]);

  if (missing.length > 0) {
    throw new EnvironmentError(
      `Missing required environment variables:\n  - ${missing.join('\n  - ')}\n\n` +
      'Please set these variables in your .env file or environment.'
    );
  }

  if (!config.twilio.accountSid.startsWith('AC')) {
    throw new EnvironmentError('TWILIO_ACCOUNT_SID must start with "AC"');
  }

  // Optional: validate API key format if provided
  if (config.twilio.apiKey && !config.twilio.apiKey.startsWith('SK')) {
    throw new EnvironmentError('TWILIO_API_KEY must start with "SK"');
  }

  // Optional: validate TwiML app SID if provided
  if (config.twilio.twimlAppSid && !config.twilio.twimlAppSid.startsWith('AP')) {
    throw new EnvironmentError('TWIML_APP_SID must start with "AP"');
  }

  if (!config.openai.apiKey.startsWith('sk-')) {
    throw new EnvironmentError('OPENAI_API_KEY must start with "sk-"');
  }

  if (!config.database.url.startsWith('postgresql://') && !config.database.url.startsWith('postgres://')) {
    throw new EnvironmentError('DATABASE_URL must be a valid PostgreSQL connection string');
  }

  return true;
}

export default config;
