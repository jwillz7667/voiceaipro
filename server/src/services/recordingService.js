/**
 * Recording Service for VoiceAI Pro
 *
 * Provides real-time recording with audio mixing from both user and AI streams.
 * Produces valid WAV files with proper headers.
 */

import fs from 'fs';
import path from 'path';
import { createReadStream, createWriteStream } from 'fs';
import { v4 as uuidv4 } from 'uuid';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import { query } from '../db/pool.js';

const logger = createLogger('recording-service');

// Recording configuration
const RECORDING_DIR = config.recording.storagePath;
const SAMPLE_RATE = 24000;          // 24kHz for quality
const BITS_PER_SAMPLE = 16;
const NUM_CHANNELS = 1;             // Mono (mixed)
const BYTES_PER_SAMPLE = BITS_PER_SAMPLE / 8;

// Buffer settings
const MIX_BUFFER_SIZE = SAMPLE_RATE * 0.5;  // 500ms of audio before mixing
const MAX_BUFFER_SIZE = SAMPLE_RATE * 5;    // 5 seconds max buffer

/**
 * Recording Session class
 * Handles real-time audio buffering and mixing for a single call
 */
class RecordingSession {
  constructor(callSid, storagePath, options = {}) {
    this.callSid = callSid;
    this.recordingId = uuidv4();
    this.storagePath = storagePath;
    this.options = options;

    // Audio buffers with timestamps
    this.userBuffer = [];           // { samples: Int16Array, timestamp: number }
    this.aiBuffer = [];             // { samples: Int16Array, timestamp: number }

    // Timing
    this.startTime = Date.now();
    this.lastMixTime = Date.now();
    this.totalSamplesWritten = 0;

    // File handling
    this.writeStream = null;
    this.headerWritten = false;
    this.isActive = true;

    // Statistics
    this.stats = {
      userChunks: 0,
      aiChunks: 0,
      mixOperations: 0,
      totalUserSamples: 0,
      totalAISamples: 0,
      peakLevel: 0,
    };

    logger.info('Recording session created', {
      callSid,
      recordingId: this.recordingId,
      storagePath,
    });
  }

  /**
   * Initialize the recording file
   */
  async initialize() {
    // Ensure directory exists
    await fs.promises.mkdir(path.dirname(this.storagePath), { recursive: true });

    // Open file for writing
    this.writeStream = createWriteStream(this.storagePath);

    // Write placeholder WAV header (44 bytes)
    const placeholderHeader = Buffer.alloc(44);
    this.writeStream.write(placeholderHeader);
    this.headerWritten = true;

    logger.debug('Recording file initialized', {
      callSid: this.callSid,
      recordingId: this.recordingId,
    });
  }

  /**
   * Append user audio (from Twilio, already converted to PCM16 24kHz)
   *
   * @param {Int16Array} samples - PCM16 samples at 24kHz
   */
  appendUserAudio(samples) {
    if (!this.isActive || !samples || samples.length === 0) {
      return;
    }

    const timestamp = Date.now() - this.startTime;

    this.userBuffer.push({
      samples: new Int16Array(samples),
      timestamp,
    });

    this.stats.userChunks++;
    this.stats.totalUserSamples += samples.length;

    // Track peak level
    for (let i = 0; i < samples.length; i++) {
      const absValue = Math.abs(samples[i]);
      if (absValue > this.stats.peakLevel) {
        this.stats.peakLevel = absValue;
      }
    }

    // Check if we should mix and write
    this.checkAndMix();
  }

  /**
   * Append AI audio (from OpenAI, PCM16 24kHz)
   *
   * @param {Int16Array} samples - PCM16 samples at 24kHz
   */
  appendAIAudio(samples) {
    if (!this.isActive || !samples || samples.length === 0) {
      return;
    }

    const timestamp = Date.now() - this.startTime;

    this.aiBuffer.push({
      samples: new Int16Array(samples),
      timestamp,
    });

    this.stats.aiChunks++;
    this.stats.totalAISamples += samples.length;

    // Track peak level
    for (let i = 0; i < samples.length; i++) {
      const absValue = Math.abs(samples[i]);
      if (absValue > this.stats.peakLevel) {
        this.stats.peakLevel = absValue;
      }
    }

    // Check if we should mix and write
    this.checkAndMix();
  }

  /**
   * Check buffer sizes and mix if threshold reached
   */
  checkAndMix() {
    const userSamples = this.userBuffer.reduce((sum, chunk) => sum + chunk.samples.length, 0);
    const aiSamples = this.aiBuffer.reduce((sum, chunk) => sum + chunk.samples.length, 0);
    const timeSinceLastMix = Date.now() - this.lastMixTime;

    // Mix if either:
    // 1. Either buffer exceeds threshold
    // 2. It's been more than 500ms since last mix and we have some audio
    const shouldMix =
      userSamples >= MIX_BUFFER_SIZE ||
      aiSamples >= MIX_BUFFER_SIZE ||
      (timeSinceLastMix > 500 && (userSamples > 0 || aiSamples > 0));

    if (shouldMix) {
      this.mixAndWrite();
    }
  }

  /**
   * Mix user and AI audio buffers and write to file
   */
  mixAndWrite() {
    if (!this.writeStream || !this.isActive) {
      return;
    }

    // Calculate how many samples to mix
    const userSamples = this.userBuffer.reduce((sum, chunk) => sum + chunk.samples.length, 0);
    const aiSamples = this.aiBuffer.reduce((sum, chunk) => sum + chunk.samples.length, 0);

    if (userSamples === 0 && aiSamples === 0) {
      return;
    }

    // Determine mix length - use the larger of the two
    const mixLength = Math.max(userSamples, aiSamples);
    const mixedSamples = new Int16Array(mixLength);

    // Flatten user buffer
    const userFlat = new Int16Array(userSamples);
    let userOffset = 0;
    for (const chunk of this.userBuffer) {
      userFlat.set(chunk.samples, userOffset);
      userOffset += chunk.samples.length;
    }

    // Flatten AI buffer
    const aiFlat = new Int16Array(aiSamples);
    let aiOffset = 0;
    for (const chunk of this.aiBuffer) {
      aiFlat.set(chunk.samples, aiOffset);
      aiOffset += chunk.samples.length;
    }

    // Mix the audio streams
    // Simple mixing with averaging to prevent clipping
    for (let i = 0; i < mixLength; i++) {
      const userSample = i < userFlat.length ? userFlat[i] : 0;
      const aiSample = i < aiFlat.length ? aiFlat[i] : 0;

      // Average the two channels (prevents clipping better than simple addition)
      let mixed = Math.round((userSample + aiSample) / 2);

      // Soft clipping for better audio quality
      if (mixed > 32767) mixed = 32767;
      if (mixed < -32768) mixed = -32768;

      mixedSamples[i] = mixed;
    }

    // Write to file
    const buffer = Buffer.from(mixedSamples.buffer);
    this.writeStream.write(buffer);

    this.totalSamplesWritten += mixLength;
    this.stats.mixOperations++;
    this.lastMixTime = Date.now();

    // Clear buffers
    this.userBuffer = [];
    this.aiBuffer = [];

    logger.trace('Audio mixed and written', {
      callSid: this.callSid,
      mixLength,
      totalWritten: this.totalSamplesWritten,
    });
  }

  /**
   * Stop recording and finalize the file
   *
   * @returns {Promise<Object>} Recording metadata
   */
  async stop() {
    if (!this.isActive) {
      logger.warn('Recording already stopped', { callSid: this.callSid });
      return null;
    }

    this.isActive = false;

    // Final mix of any remaining audio
    this.mixAndWrite();

    // Calculate final size
    const dataSize = this.totalSamplesWritten * BYTES_PER_SAMPLE;
    const durationSeconds = Math.floor(this.totalSamplesWritten / SAMPLE_RATE);

    // Close write stream
    if (this.writeStream) {
      await new Promise((resolve, reject) => {
        this.writeStream.end((err) => {
          if (err) reject(err);
          else resolve();
        });
      });
    }

    // Update WAV header with correct sizes
    await this.updateWavHeader(dataSize);

    // Get final file stats
    const fileStats = await fs.promises.stat(this.storagePath);

    logger.info('Recording stopped', {
      callSid: this.callSid,
      recordingId: this.recordingId,
      durationSeconds,
      fileSizeBytes: fileStats.size,
      stats: this.stats,
    });

    return {
      recordingId: this.recordingId,
      storagePath: this.storagePath,
      durationSeconds,
      fileSizeBytes: fileStats.size,
      sampleRate: SAMPLE_RATE,
      stats: this.stats,
    };
  }

  /**
   * Update WAV header with correct file sizes
   *
   * @param {number} dataSize - Size of audio data in bytes
   */
  async updateWavHeader(dataSize) {
    const header = createWavHeader(dataSize, SAMPLE_RATE);

    // Open file for random access
    const fd = await fs.promises.open(this.storagePath, 'r+');
    try {
      await fd.write(header, 0, header.length, 0);
    } finally {
      await fd.close();
    }

    logger.debug('WAV header updated', {
      callSid: this.callSid,
      dataSize,
    });
  }

  /**
   * Get recording statistics
   *
   * @returns {Object} Current recording stats
   */
  getStats() {
    const elapsedSeconds = (Date.now() - this.startTime) / 1000;
    const durationSeconds = this.totalSamplesWritten / SAMPLE_RATE;

    return {
      recordingId: this.recordingId,
      callSid: this.callSid,
      isActive: this.isActive,
      elapsedSeconds,
      recordedDurationSeconds: durationSeconds,
      totalSamplesWritten: this.totalSamplesWritten,
      userBufferSize: this.userBuffer.reduce((sum, c) => sum + c.samples.length, 0),
      aiBufferSize: this.aiBuffer.reduce((sum, c) => sum + c.samples.length, 0),
      ...this.stats,
    };
  }
}

/**
 * Create WAV header
 *
 * @param {number} dataSize - Size of audio data in bytes
 * @param {number} sampleRate - Sample rate in Hz
 * @returns {Buffer} WAV header
 */
function createWavHeader(dataSize, sampleRate = SAMPLE_RATE) {
  const header = Buffer.alloc(44);

  const byteRate = sampleRate * NUM_CHANNELS * BYTES_PER_SAMPLE;
  const blockAlign = NUM_CHANNELS * BYTES_PER_SAMPLE;

  // RIFF header
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataSize, 4);       // File size - 8
  header.write('WAVE', 8);

  // fmt chunk
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);                 // Chunk size
  header.writeUInt16LE(1, 20);                  // Audio format (PCM)
  header.writeUInt16LE(NUM_CHANNELS, 22);       // Number of channels
  header.writeUInt32LE(sampleRate, 24);         // Sample rate
  header.writeUInt32LE(byteRate, 28);           // Byte rate
  header.writeUInt16LE(blockAlign, 32);         // Block align
  header.writeUInt16LE(BITS_PER_SAMPLE, 34);    // Bits per sample

  // data chunk
  header.write('data', 36);
  header.writeUInt32LE(dataSize, 40);           // Data size

  return header;
}

// Active recording sessions
const activeRecordings = new Map();

/**
 * Start a new recording session
 *
 * @param {string} callSid - Call SID to record
 * @param {Object} [options] - Recording options
 * @returns {Promise<RecordingSession>} Recording session
 */
export async function startRecording(callSid, options = {}) {
  // Check if already recording
  if (activeRecordings.has(callSid)) {
    logger.warn('Recording already exists for call', { callSid });
    return activeRecordings.get(callSid);
  }

  // Ensure recording directory exists
  await fs.promises.mkdir(RECORDING_DIR, { recursive: true });

  const recordingId = uuidv4();
  const filename = `${recordingId}.wav`;
  const storagePath = path.join(RECORDING_DIR, filename);

  const session = new RecordingSession(callSid, storagePath, options);
  await session.initialize();

  activeRecordings.set(callSid, session);

  logger.info('Recording started', {
    callSid,
    recordingId,
    storagePath,
  });

  return session;
}

/**
 * Append user audio to a recording
 *
 * @param {string} callSid - Call SID
 * @param {Int16Array} samples - PCM16 samples at 24kHz
 */
export function appendUserAudio(callSid, samples) {
  const session = activeRecordings.get(callSid);
  if (session) {
    session.appendUserAudio(samples);
  }
}

/**
 * Append AI audio to a recording
 *
 * @param {string} callSid - Call SID
 * @param {Int16Array} samples - PCM16 samples at 24kHz
 */
export function appendAIAudio(callSid, samples) {
  const session = activeRecordings.get(callSid);
  if (session) {
    session.appendAIAudio(samples);
  }
}

/**
 * Stop a recording and save to database
 *
 * @param {string} callSid - Call SID
 * @returns {Promise<Object|null>} Recording metadata or null
 */
export async function stopRecording(callSid) {
  const session = activeRecordings.get(callSid);
  if (!session) {
    logger.debug('No active recording for call', { callSid });
    return null;
  }

  try {
    const metadata = await session.stop();

    if (!metadata || metadata.durationSeconds < 1) {
      // Recording too short, delete it
      logger.info('Recording too short, discarding', { callSid });
      try {
        await fs.promises.unlink(metadata.storagePath);
      } catch (e) {
        // Ignore
      }
      activeRecordings.delete(callSid);
      return null;
    }

    // Get call session ID from database
    const sessionResult = await query(
      'SELECT id FROM call_sessions WHERE call_sid = $1',
      [callSid]
    );

    if (sessionResult.rows.length === 0) {
      logger.warn('Call session not found in database', { callSid });
      activeRecordings.delete(callSid);
      return metadata;
    }

    const callSessionId = sessionResult.rows[0].id;

    // Save to database
    const dbResult = await query(
      `INSERT INTO recordings (id, call_session_id, storage_path, duration_seconds, file_size_bytes, format)
       VALUES ($1, $2, $3, $4, $5, 'wav')
       RETURNING id, storage_path, duration_seconds, file_size_bytes, format, created_at`,
      [
        metadata.recordingId,
        callSessionId,
        metadata.storagePath,
        metadata.durationSeconds,
        metadata.fileSizeBytes,
      ]
    );

    logger.info('Recording saved to database', {
      callSid,
      recordingId: metadata.recordingId,
      durationSeconds: metadata.durationSeconds,
    });

    activeRecordings.delete(callSid);

    return {
      ...metadata,
      ...dbResult.rows[0],
    };
  } catch (error) {
    logger.error('Failed to stop recording', { callSid, error: error.message });
    activeRecordings.delete(callSid);
    throw error;
  }
}

/**
 * Check if recording is active for a call
 *
 * @param {string} callSid - Call SID
 * @returns {boolean} True if recording is active
 */
export function isRecording(callSid) {
  const session = activeRecordings.get(callSid);
  return session?.isActive ?? false;
}

/**
 * Get recording stats for a call
 *
 * @param {string} callSid - Call SID
 * @returns {Object|null} Recording stats or null
 */
export function getRecordingStats(callSid) {
  const session = activeRecordings.get(callSid);
  return session?.getStats() ?? null;
}

/**
 * Get recording stream for playback
 *
 * @param {string} storagePath - Path to recording file
 * @returns {Promise<ReadStream>} File read stream
 */
export async function getRecordingStream(storagePath) {
  try {
    await fs.promises.access(storagePath, fs.constants.R_OK);
    return createReadStream(storagePath);
  } catch (error) {
    logger.error('Recording file not found', { storagePath, error: error.message });
    throw new Error(`Recording file not found: ${storagePath}`);
  }
}

/**
 * Delete a recording file
 *
 * @param {string} storagePath - Path to recording file
 * @returns {Promise<boolean>} True if deleted
 */
export async function deleteRecording(storagePath) {
  try {
    await fs.promises.unlink(storagePath);
    logger.info('Recording file deleted', { storagePath });
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') {
      logger.warn('Recording file already deleted', { storagePath });
      return true;
    }
    logger.error('Failed to delete recording file', { storagePath, error: error.message });
    throw error;
  }
}

/**
 * Get recording metadata by ID
 *
 * @param {string} recordingId - Recording UUID
 * @returns {Promise<Object|null>} Recording metadata or null
 */
export async function getRecordingMetadata(recordingId) {
  const result = await query(
    `SELECT r.*, cs.call_sid, cs.phone_number, cs.direction
     FROM recordings r
     JOIN call_sessions cs ON r.call_session_id = cs.id
     WHERE r.id = $1`,
    [recordingId]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * List recordings with optional filters
 *
 * @param {Object} [options] - Query options
 * @returns {Promise<Object[]>} Recordings list
 */
export async function listRecordings(options = {}) {
  const { userId, callSid, limit = 50, offset = 0 } = options;

  let queryText = `
    SELECT r.id, r.storage_path, r.duration_seconds, r.file_size_bytes,
           r.format, r.created_at, cs.call_sid, cs.phone_number, cs.direction
    FROM recordings r
    JOIN call_sessions cs ON r.call_session_id = cs.id
    WHERE 1=1
  `;
  const params = [];
  let paramIndex = 1;

  if (userId) {
    queryText += ` AND cs.user_id = $${paramIndex++}`;
    params.push(userId);
  }

  if (callSid) {
    queryText += ` AND cs.call_sid = $${paramIndex++}`;
    params.push(callSid);
  }

  queryText += ` ORDER BY r.created_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const result = await query(queryText, params);
  return result.rows;
}

/**
 * Get storage statistics
 *
 * @returns {Promise<Object>} Storage stats
 */
export async function getStorageStats() {
  try {
    const files = await fs.promises.readdir(RECORDING_DIR).catch(() => []);
    let totalSize = 0;
    let fileCount = 0;

    for (const file of files) {
      try {
        const filePath = path.join(RECORDING_DIR, file);
        const stats = await fs.promises.stat(filePath);
        if (stats.isFile()) {
          totalSize += stats.size;
          fileCount++;
        }
      } catch (e) {
        // Ignore individual file errors
      }
    }

    const dbResult = await query(
      'SELECT COUNT(*) as count, COALESCE(SUM(duration_seconds), 0) as total_duration FROM recordings'
    );

    return {
      fileCount,
      totalSizeBytes: totalSize,
      totalSizeMB: (totalSize / (1024 * 1024)).toFixed(2),
      dbRecordCount: parseInt(dbResult.rows[0].count),
      totalDurationSeconds: parseInt(dbResult.rows[0].total_duration),
      activeRecordings: activeRecordings.size,
    };
  } catch (error) {
    logger.error('Failed to get storage stats', { error: error.message });
    throw error;
  }
}

/**
 * Cleanup orphaned recording files
 *
 * @returns {Promise<Object>} Cleanup results
 */
export async function cleanupOrphanedFiles() {
  try {
    const files = await fs.promises.readdir(RECORDING_DIR).catch(() => []);

    const dbResult = await query('SELECT storage_path FROM recordings');
    const dbPaths = new Set(dbResult.rows.map((r) => r.storage_path));

    // Also exclude active recordings
    const activePaths = new Set();
    for (const session of activeRecordings.values()) {
      activePaths.add(session.storagePath);
    }

    let deletedCount = 0;
    let deletedSize = 0;

    for (const file of files) {
      const filePath = path.join(RECORDING_DIR, file);
      if (!dbPaths.has(filePath) && !activePaths.has(filePath)) {
        try {
          const stats = await fs.promises.stat(filePath);
          await fs.promises.unlink(filePath);
          deletedCount++;
          deletedSize += stats.size;
          logger.info('Deleted orphaned recording file', { filePath });
        } catch (e) {
          // Ignore errors
        }
      }
    }

    logger.info('Orphaned file cleanup complete', {
      deletedCount,
      deletedSizeBytes: deletedSize,
    });

    return { deletedCount, deletedSizeBytes: deletedSize };
  } catch (error) {
    logger.error('Failed to cleanup orphaned files', { error: error.message });
    throw error;
  }
}

/**
 * Abort recording without saving
 *
 * @param {string} callSid - Call SID
 * @returns {Promise<boolean>} True if aborted
 */
export async function abortRecording(callSid) {
  const session = activeRecordings.get(callSid);
  if (!session) {
    return false;
  }

  session.isActive = false;

  if (session.writeStream) {
    session.writeStream.end();
  }

  try {
    await fs.promises.unlink(session.storagePath);
  } catch (e) {
    // Ignore
  }

  activeRecordings.delete(callSid);
  logger.info('Recording aborted', { callSid });

  return true;
}

// Export the RecordingSession class for advanced usage
export { RecordingSession };

export default {
  startRecording,
  appendUserAudio,
  appendAIAudio,
  stopRecording,
  abortRecording,
  isRecording,
  getRecordingStats,
  getRecordingStream,
  deleteRecording,
  getRecordingMetadata,
  listRecordings,
  getStorageStats,
  cleanupOrphanedFiles,
  RecordingSession,
};
