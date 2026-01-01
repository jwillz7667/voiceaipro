import config from '../config/environment.js';

const LOG_LEVELS = {
  error: 0,
  warn: 1,
  info: 2,
  debug: 3,
  trace: 4,
};

const LEVEL_COLORS = {
  error: '\x1b[31m',
  warn: '\x1b[33m',
  info: '\x1b[36m',
  debug: '\x1b[35m',
  trace: '\x1b[90m',
};

const RESET = '\x1b[0m';

class Logger {
  constructor(context = 'app') {
    this.context = context;
    this.level = LOG_LEVELS[config.logging.level] ?? LOG_LEVELS.info;
    this.prettyPrint = config.logging.prettyPrint;
  }

  child(childContext) {
    return new Logger(`${this.context}:${childContext}`);
  }

  formatMessage(level, message, data) {
    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level,
      context: this.context,
      message,
      ...(data && Object.keys(data).length > 0 ? { data } : {}),
    };

    if (this.prettyPrint) {
      const color = LEVEL_COLORS[level] || '';
      const levelPadded = level.toUpperCase().padEnd(5);
      const dataStr = data && Object.keys(data).length > 0
        ? `\n${JSON.stringify(data, null, 2)}`
        : '';
      return `${color}[${timestamp}] ${levelPadded}${RESET} [${this.context}] ${message}${dataStr}`;
    }

    return JSON.stringify(logEntry);
  }

  log(level, message, data) {
    if (LOG_LEVELS[level] > this.level) return;

    const formatted = this.formatMessage(level, message, data);
    const output = level === 'error' ? console.error : console.log;
    output(formatted);
  }

  error(message, data) {
    if (data instanceof Error) {
      this.log('error', message, {
        error: data.message,
        stack: data.stack,
        name: data.name,
      });
    } else {
      this.log('error', message, data);
    }
  }

  warn(message, data) {
    this.log('warn', message, data);
  }

  info(message, data) {
    this.log('info', message, data);
  }

  debug(message, data) {
    this.log('debug', message, data);
  }

  trace(message, data) {
    this.log('trace', message, data);
  }

  request(req, res, duration) {
    this.info('HTTP Request', {
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      userAgent: req.get('user-agent'),
    });
  }

  wsEvent(event, data) {
    this.debug(`WebSocket Event: ${event}`, data);
  }

  callEvent(callSid, event, data) {
    this.info(`Call Event: ${event}`, {
      callSid,
      ...data,
    });
  }
}

const logger = new Logger('voiceai');

export function createLogger(context) {
  return logger.child(context);
}

export function requestLogger() {
  const httpLogger = createLogger('http');

  return (req, res, next) => {
    const start = Date.now();

    res.on('finish', () => {
      const duration = Date.now() - start;
      httpLogger.request(req, res, duration);
    });

    next();
  };
}

export default logger;
