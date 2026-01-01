import fs from 'fs';
import path from 'path';
import { createReadStream, createWriteStream } from 'fs';
import { pipeline } from 'stream/promises';
import { v4 as uuidv4 } from 'uuid';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import { query } from '../db/pool.js';
import { decodeMulaw, int16ArrayToBuffer } from '../audio/converter.js';

const logger = createLogger('recording-service');

const RECORDING_DIR = config.recording.storagePath;
const DEFAULT_SAMPLE_RATE = 8000;
const BITS_PER_SAMPLE = 16;
const NUM_CHANNELS = 1;

async function ensureRecordingDirectory() {
  try {
    await fs.promises.mkdir(RECORDING_DIR, { recursive: true });
  } catch (error) {
    if (error.code !== 'EEXIST') {
      throw error;
    }
  }
}

function createWavHeader(dataSize, sampleRate = DEFAULT_SAMPLE_RATE) {
  const header = Buffer.alloc(44);

  const byteRate = sampleRate * NUM_CHANNELS * (BITS_PER_SAMPLE / 8);
  const blockAlign = NUM_CHANNELS * (BITS_PER_SAMPLE / 8);

  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataSize, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(NUM_CHANNELS, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(BITS_PER_SAMPLE, 34);
  header.write('data', 36);
  header.writeUInt32LE(dataSize, 40);

  return header;
}

export async function saveRecording(callSessionId, audioChunks, options = {}) {
  await ensureRecordingDirectory();

  const recordingId = uuidv4();
  const format = options.format || config.recording.format || 'wav';
  const filename = `${recordingId}.${format}`;
  const storagePath = path.join(RECORDING_DIR, filename);

  logger.info('Saving recording', {
    recordingId,
    callSessionId,
    chunkCount: audioChunks.length,
    storagePath,
  });

  try {
    const allPcmData = [];
    let totalSamples = 0;

    for (const chunk of audioChunks) {
      if (chunk.audio) {
        const mulawBuffer = Buffer.from(chunk.audio, 'base64');
        const mulawUint8 = new Uint8Array(mulawBuffer);
        const pcmSamples = decodeMulaw(mulawUint8);
        const pcmBuffer = int16ArrayToBuffer(pcmSamples);
        allPcmData.push(pcmBuffer);
        totalSamples += pcmSamples.length;
      }
    }

    const totalDataSize = totalSamples * 2;
    const wavHeader = createWavHeader(totalDataSize, DEFAULT_SAMPLE_RATE);

    const writeStream = createWriteStream(storagePath);

    writeStream.write(wavHeader);

    for (const pcmBuffer of allPcmData) {
      writeStream.write(pcmBuffer);
    }

    await new Promise((resolve, reject) => {
      writeStream.on('finish', resolve);
      writeStream.on('error', reject);
      writeStream.end();
    });

    const stats = await fs.promises.stat(storagePath);
    const durationSeconds = Math.floor(totalSamples / DEFAULT_SAMPLE_RATE);

    const result = await query(
      `INSERT INTO recordings (id, call_session_id, storage_path, duration_seconds, file_size_bytes, format)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, storage_path, duration_seconds, file_size_bytes, format, created_at`,
      [recordingId, callSessionId, storagePath, durationSeconds, stats.size, format]
    );

    logger.info('Recording saved successfully', {
      recordingId,
      durationSeconds,
      fileSizeBytes: stats.size,
    });

    return result.rows[0];
  } catch (error) {
    logger.error('Failed to save recording', { callSessionId, error });

    try {
      await fs.promises.unlink(storagePath);
    } catch (unlinkError) {
      logger.debug('Failed to clean up incomplete recording file', { error: unlinkError.message });
    }

    throw error;
  }
}

export async function getRecordingStream(storagePath) {
  try {
    await fs.promises.access(storagePath, fs.constants.R_OK);
    return createReadStream(storagePath);
  } catch (error) {
    logger.error('Recording file not found', { storagePath, error: error.message });
    throw new Error(`Recording file not found: ${storagePath}`);
  }
}

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

export async function getRecordingMetadata(recordingId) {
  const result = await query(
    `SELECT r.*, cs.call_sid, cs.phone_number, cs.direction
     FROM recordings r
     JOIN call_sessions cs ON r.call_session_id = cs.id
     WHERE r.id = $1`,
    [recordingId]
  );

  if (result.rows.length === 0) {
    return null;
  }

  return result.rows[0];
}

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

export async function getStorageStats() {
  try {
    const files = await fs.promises.readdir(RECORDING_DIR);
    let totalSize = 0;
    let fileCount = 0;

    for (const file of files) {
      const filePath = path.join(RECORDING_DIR, file);
      const stats = await fs.promises.stat(filePath);
      if (stats.isFile()) {
        totalSize += stats.size;
        fileCount++;
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
    };
  } catch (error) {
    logger.error('Failed to get storage stats', { error: error.message });
    throw error;
  }
}

export async function cleanupOrphanedFiles() {
  try {
    const files = await fs.promises.readdir(RECORDING_DIR);

    const dbResult = await query('SELECT storage_path FROM recordings');
    const dbPaths = new Set(dbResult.rows.map((r) => r.storage_path));

    let deletedCount = 0;
    let deletedSize = 0;

    for (const file of files) {
      const filePath = path.join(RECORDING_DIR, file);
      if (!dbPaths.has(filePath)) {
        const stats = await fs.promises.stat(filePath);
        await fs.promises.unlink(filePath);
        deletedCount++;
        deletedSize += stats.size;
        logger.info('Deleted orphaned recording file', { filePath });
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

export async function processCallRecording(session) {
  if (!session.isRecording || !session.recordingBuffer) {
    logger.debug('No recording to process', { callSid: session.callSid });
    return null;
  }

  const audioChunks = session.getRecordingBuffer();

  if (audioChunks.length === 0) {
    logger.debug('Empty recording buffer', { callSid: session.callSid });
    return null;
  }

  logger.info('Processing call recording', {
    callSid: session.callSid,
    chunkCount: audioChunks.length,
  });

  const sessionResult = await query(
    'SELECT id FROM call_sessions WHERE call_sid = $1',
    [session.callSid]
  );

  if (sessionResult.rows.length === 0) {
    logger.warn('Call session not found in database', { callSid: session.callSid });
    return null;
  }

  const callSessionId = sessionResult.rows[0].id;

  return saveRecording(callSessionId, audioChunks);
}

export default {
  saveRecording,
  getRecordingStream,
  deleteRecording,
  getRecordingMetadata,
  listRecordings,
  getStorageStats,
  cleanupOrphanedFiles,
  processCallRecording,
};
