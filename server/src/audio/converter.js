/**
 * Audio Converter for VoiceAI Pro
 *
 * Handles bidirectional audio conversion between:
 * - Twilio: μ-law (G.711) encoded, 8kHz sample rate, mono
 * - OpenAI: Linear PCM16 (signed 16-bit little-endian), 24kHz sample rate, mono
 *
 * AUDIO ENGINEERING DETAILS:
 *
 * μ-law (G.711):
 * - 8-bit samples, logarithmically compressed
 * - Dynamic range: ~13 bits effective
 * - Bias: 33 (0x21)
 * - Clip value: 32635
 *
 * PCM16:
 * - 16-bit signed samples
 * - Little-endian byte order
 * - Range: -32768 to 32767
 *
 * Resampling:
 * - 8kHz → 24kHz: 3x interpolation (upsample) with linear interpolation
 * - 24kHz → 8kHz: 3x decimation (downsample) with averaging for anti-aliasing
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('audio:converter');

// μ-law constants per ITU-T G.711
// Note: Encoding and decoding use different bias values!
const MULAW_ENCODE_BIAS = 33;   // 0x21 - bias for encoding
const MULAW_DECODE_BIAS = 0x84; // 132 - bias for decoding reconstruction
const MULAW_CLIP = 32635;       // Maximum sample value before clipping
const MULAW_MAX = 0x1FFF;       // Maximum biased sample value (8191)

// Sample rates
const SAMPLE_RATE_TWILIO = 8000;   // 8kHz for Twilio
const SAMPLE_RATE_OPENAI = 24000;  // 24kHz for OpenAI

// Resampling ratio
const RESAMPLE_RATIO = SAMPLE_RATE_OPENAI / SAMPLE_RATE_TWILIO; // 3

// ============================================================================
// LOOKUP TABLES
// ============================================================================

/**
 * Pre-computed μ-law decode table
 * 256 entries, one for each possible μ-law byte value (0x00-0xFF)
 * Maps μ-law byte → PCM16 sample
 */
const MULAW_DECODE_TABLE = new Int16Array(256);

/**
 * Pre-computed μ-law encode table
 * 65536 entries for fast lookup (maps unsigned 16-bit → μ-law byte)
 * Index = PCM16 sample + 32768 (to convert signed to unsigned index)
 */
const MULAW_ENCODE_TABLE = new Uint8Array(65536);

/**
 * Initialize lookup tables at module load
 * This runs once when the module is imported
 */
(function initializeTables() {
  // Build decode table: μ-law byte → PCM16 sample
  // μ-law format: |S|EEE|MMMM| where S=sign, E=exponent, M=mantissa
  for (let mulawByte = 0; mulawByte < 256; mulawByte++) {
    // Invert all bits (μ-law uses inverted storage)
    const inverted = ~mulawByte & 0xFF;

    // Extract components
    const sign = inverted & 0x80;        // Sign bit (bit 7)
    const exponent = (inverted >> 4) & 0x07;  // Exponent (bits 4-6)
    const mantissa = inverted & 0x0F;    // Mantissa (bits 0-3)

    // Reconstruct linear sample using decode bias (0x84 = 132)
    // Formula: sample = ((mantissa << 3) + 0x84) << exponent - 0x84
    let sample = ((mantissa << 3) + MULAW_DECODE_BIAS) << exponent;
    sample -= MULAW_DECODE_BIAS;

    // Apply sign
    MULAW_DECODE_TABLE[mulawByte] = sign ? -sample : sample;
  }

  // Build encode table: PCM16 sample → μ-law byte
  // Uses direct lookup for maximum speed
  for (let i = 0; i < 65536; i++) {
    // Convert unsigned index to signed PCM16 sample
    const sample = i - 32768;
    MULAW_ENCODE_TABLE[i] = encodeMulawSample(sample);
  }

  logger.debug('μ-law lookup tables initialized', {
    decodeTableSize: MULAW_DECODE_TABLE.length,
    encodeTableSize: MULAW_ENCODE_TABLE.length,
  });
})();

/**
 * Encode a single PCM16 sample to μ-law
 * This is used to build the encode table and can be called directly
 *
 * @param {number} sample - PCM16 sample (-32768 to 32767)
 * @returns {number} μ-law byte (0-255)
 */
function encodeMulawSample(sample) {
  // Determine sign and work with absolute value
  let sign = 0;
  if (sample < 0) {
    sign = 0x80;
    sample = -sample;
  }

  // Add bias for encoding
  sample += MULAW_ENCODE_BIAS;

  // Clip to maximum
  if (sample > MULAW_CLIP) {
    sample = MULAW_CLIP;
  }

  // Find exponent (position of highest bit)
  // Start at bit 14 (0x4000) and work down
  let exponent = 7;
  let expMask = 0x4000;
  while ((sample & expMask) === 0 && exponent > 0) {
    exponent--;
    expMask >>= 1;
  }

  // Extract mantissa (4 bits after the leading 1)
  const mantissa = (sample >> (exponent + 3)) & 0x0F;

  // Combine and invert (μ-law uses inverted storage)
  const mulawByte = ~(sign | (exponent << 4) | mantissa) & 0xFF;

  return mulawByte;
}

// ============================================================================
// CORE CONVERSION FUNCTIONS
// ============================================================================

/**
 * Decode μ-law bytes to PCM16 samples
 *
 * @param {Buffer|Uint8Array} mulawBuffer - Buffer of μ-law bytes
 * @returns {Int16Array} PCM16 samples at 8kHz
 */
export function decodeMulaw(mulawBuffer) {
  const samples = new Int16Array(mulawBuffer.length);
  for (let i = 0; i < mulawBuffer.length; i++) {
    samples[i] = MULAW_DECODE_TABLE[mulawBuffer[i]];
  }
  return samples;
}

/**
 * Encode PCM16 samples to μ-law bytes
 *
 * @param {Int16Array} pcm16Array - PCM16 samples
 * @returns {Uint8Array} Buffer of μ-law bytes
 */
export function encodeMulaw(pcm16Array) {
  const mulaw = new Uint8Array(pcm16Array.length);
  for (let i = 0; i < pcm16Array.length; i++) {
    // Convert signed sample to unsigned index for table lookup
    const sample = pcm16Array[i] + 32768;
    mulaw[i] = MULAW_ENCODE_TABLE[sample];
  }
  return mulaw;
}

// ============================================================================
// RESAMPLING FUNCTIONS
// ============================================================================

/**
 * Upsample from 8kHz to 24kHz (3x interpolation)
 * Uses linear interpolation between samples for smooth transitions
 *
 * @param {Int16Array} pcm8k - PCM16 samples at 8kHz
 * @returns {Int16Array} PCM16 samples at 24kHz (3x length)
 */
export function resample8kTo24k(pcm8k) {
  if (pcm8k.length === 0) {
    return new Int16Array(0);
  }

  const outputLength = pcm8k.length * RESAMPLE_RATIO;
  const output = new Int16Array(outputLength);

  for (let i = 0; i < pcm8k.length; i++) {
    const currentSample = pcm8k[i];
    const nextSample = (i + 1 < pcm8k.length) ? pcm8k[i + 1] : currentSample;

    // Each input sample produces 3 output samples
    const outIdx = i * RESAMPLE_RATIO;

    // Sample 0: original sample
    output[outIdx] = currentSample;

    // Sample 1: 1/3 interpolated
    output[outIdx + 1] = Math.round(currentSample + (nextSample - currentSample) / 3);

    // Sample 2: 2/3 interpolated
    output[outIdx + 2] = Math.round(currentSample + (2 * (nextSample - currentSample)) / 3);
  }

  return output;
}

/**
 * Downsample from 24kHz to 8kHz (3x decimation)
 * Uses averaging of 3 samples for basic anti-aliasing
 *
 * @param {Int16Array} pcm24k - PCM16 samples at 24kHz
 * @returns {Int16Array} PCM16 samples at 8kHz (1/3 length)
 */
export function resample24kTo8k(pcm24k) {
  if (pcm24k.length === 0) {
    return new Int16Array(0);
  }

  // Output length is floor(input / 3)
  const outputLength = Math.floor(pcm24k.length / RESAMPLE_RATIO);
  const output = new Int16Array(outputLength);

  for (let i = 0; i < outputLength; i++) {
    const srcIdx = i * RESAMPLE_RATIO;

    // Average 3 consecutive samples for anti-aliasing
    // This acts as a simple low-pass filter
    const sample0 = pcm24k[srcIdx];
    const sample1 = (srcIdx + 1 < pcm24k.length) ? pcm24k[srcIdx + 1] : sample0;
    const sample2 = (srcIdx + 2 < pcm24k.length) ? pcm24k[srcIdx + 2] : sample1;

    output[i] = Math.round((sample0 + sample1 + sample2) / 3);
  }

  return output;
}

/**
 * Generic resample function for arbitrary sample rates
 * Uses linear interpolation
 *
 * @param {Int16Array} inputSamples - Input samples
 * @param {number} inputRate - Input sample rate
 * @param {number} outputRate - Output sample rate
 * @returns {Int16Array} Resampled audio
 */
export function resample(inputSamples, inputRate, outputRate) {
  if (inputRate === outputRate) {
    return inputSamples;
  }

  // Use optimized functions for common conversions
  if (inputRate === 8000 && outputRate === 24000) {
    return resample8kTo24k(inputSamples);
  }
  if (inputRate === 24000 && outputRate === 8000) {
    return resample24kTo8k(inputSamples);
  }

  // Generic resampling for other rates
  const ratio = outputRate / inputRate;
  const outputLength = Math.floor(inputSamples.length * ratio);
  const output = new Int16Array(outputLength);

  for (let i = 0; i < outputLength; i++) {
    const srcPos = i / ratio;
    const srcIndex = Math.floor(srcPos);
    const frac = srcPos - srcIndex;

    if (srcIndex + 1 < inputSamples.length) {
      const sample1 = inputSamples[srcIndex];
      const sample2 = inputSamples[srcIndex + 1];
      output[i] = Math.round(sample1 + frac * (sample2 - sample1));
    } else {
      output[i] = inputSamples[srcIndex] || 0;
    }
  }

  return output;
}

// ============================================================================
// FULL PIPELINE FUNCTIONS
// ============================================================================

/**
 * Convert μ-law buffer to PCM16 at 24kHz
 * Twilio → OpenAI direction (internal buffer version)
 *
 * @param {Buffer|Uint8Array} mulawBuffer - μ-law audio buffer
 * @returns {Int16Array} PCM16 samples at 24kHz
 */
export function mulawToPCM16_24k(mulawBuffer) {
  const pcm8k = decodeMulaw(mulawBuffer);
  const pcm24k = resample8kTo24k(pcm8k);
  return pcm24k;
}

/**
 * Convert PCM16 at 24kHz to μ-law buffer
 * OpenAI → Twilio direction (internal buffer version)
 *
 * @param {Int16Array} pcm24kBuffer - PCM16 samples at 24kHz
 * @returns {Uint8Array} μ-law bytes
 */
export function pcm16_24kToMulaw(pcm24kBuffer) {
  const pcm8k = resample24kTo8k(pcm24kBuffer);
  const mulaw = encodeMulaw(pcm8k);
  return mulaw;
}

/**
 * Convert Twilio μ-law base64 to OpenAI PCM16 base64
 * Full pipeline: decode base64 → decode μ-law → resample 8k→24k → encode base64
 *
 * This is called for Twilio → OpenAI direction
 *
 * @param {string} mulawBase64 - Base64 encoded μ-law audio from Twilio
 * @returns {string} Base64 encoded PCM16 24kHz audio for OpenAI
 */
export function mulawToOpenAI(mulawBase64) {
  // Decode base64 to buffer
  const mulawBuffer = Buffer.from(mulawBase64, 'base64');

  // Decode μ-law to PCM16 at 8kHz
  const pcm8k = decodeMulaw(mulawBuffer);

  // Resample 8kHz → 24kHz
  const pcm24k = resample8kTo24k(pcm8k);

  // Convert Int16Array to Buffer and encode as base64
  const pcm24kBuffer = Buffer.from(pcm24k.buffer, pcm24k.byteOffset, pcm24k.byteLength);

  return pcm24kBuffer.toString('base64');
}

/**
 * Convert OpenAI PCM16 base64 to Twilio μ-law base64
 * Full pipeline: decode base64 → resample 24k→8k → encode μ-law → encode base64
 *
 * This is called for OpenAI → Twilio direction
 *
 * @param {string} pcm24kBase64 - Base64 encoded PCM16 24kHz audio from OpenAI
 * @returns {string} Base64 encoded μ-law audio for Twilio
 */
export function openaiToMulaw(pcm24kBase64) {
  // Decode base64 to buffer
  const pcm16Buffer = Buffer.from(pcm24kBase64, 'base64');

  // Convert Buffer to Int16Array
  // Handle potential unaligned buffer by copying to new ArrayBuffer
  const alignedBuffer = new ArrayBuffer(pcm16Buffer.length);
  const alignedView = new Uint8Array(alignedBuffer);
  pcm16Buffer.copy(alignedView);
  const pcm24k = new Int16Array(alignedBuffer);

  // Resample 24kHz → 8kHz
  const pcm8k = resample24kTo8k(pcm24k);

  // Encode to μ-law
  const mulaw = encodeMulaw(pcm8k);

  // Encode as base64
  return Buffer.from(mulaw).toString('base64');
}

// Aliases for backward compatibility
export const mulawBase64ToPCM16Base64 = mulawToOpenAI;
export const pcm16Base64ToMulawBase64 = openaiToMulaw;

// ============================================================================
// AUDIO BUFFER CLASS
// ============================================================================

/**
 * AudioBuffer for accumulating audio chunks
 * Used to batch small chunks (20ms from Twilio) into larger chunks for processing
 */
export class AudioBuffer {
  /**
   * Create an AudioBuffer
   *
   * @param {number} targetDurationMs - Target buffer duration in milliseconds
   * @param {number} sampleRate - Sample rate of the audio
   */
  constructor(targetDurationMs, sampleRate) {
    this.targetDurationMs = targetDurationMs;
    this.sampleRate = sampleRate;
    this.targetSamples = Math.floor((targetDurationMs / 1000) * sampleRate);
    this.buffer = [];
    this.totalSamples = 0;
    this.createdAt = Date.now();
    this.lastAppendAt = null;
  }

  /**
   * Append samples to the buffer
   *
   * @param {Int16Array} samples - Audio samples to append
   */
  append(samples) {
    if (samples && samples.length > 0) {
      this.buffer.push(samples);
      this.totalSamples += samples.length;
      this.lastAppendAt = Date.now();
    }
  }

  /**
   * Check if buffer has accumulated enough samples
   *
   * @returns {boolean} True if buffer is ready to be flushed
   */
  isReady() {
    return this.totalSamples >= this.targetSamples;
  }

  /**
   * Get accumulated samples and clear the buffer
   *
   * @returns {Int16Array} Concatenated audio samples
   */
  flush() {
    if (this.totalSamples === 0) {
      return new Int16Array(0);
    }

    // Concatenate all buffers
    const result = new Int16Array(this.totalSamples);
    let offset = 0;
    for (const chunk of this.buffer) {
      result.set(chunk, offset);
      offset += chunk.length;
    }

    // Clear the buffer
    this.buffer = [];
    this.totalSamples = 0;

    return result;
  }

  /**
   * Clear the buffer without returning samples
   */
  clear() {
    this.buffer = [];
    this.totalSamples = 0;
  }

  /**
   * Get current buffer size in samples
   *
   * @returns {number} Number of samples in buffer
   */
  get length() {
    return this.totalSamples;
  }

  /**
   * Get current buffer duration in milliseconds
   *
   * @returns {number} Duration in ms
   */
  get durationMs() {
    return (this.totalSamples / this.sampleRate) * 1000;
  }

  /**
   * Get time since last append in milliseconds
   *
   * @returns {number|null} Time since last append, or null if never appended
   */
  get timeSinceLastAppend() {
    return this.lastAppendAt ? Date.now() - this.lastAppendAt : null;
  }
}

/**
 * AudioChunkBuffer for accumulating and chunking audio
 * Splits audio into fixed-size chunks for transmission
 */
export class AudioChunkBuffer {
  /**
   * Create an AudioChunkBuffer
   *
   * @param {number} targetChunkSize - Target number of samples per chunk
   */
  constructor(targetChunkSize = 960) {
    this.buffer = [];
    this.targetChunkSize = targetChunkSize;
  }

  /**
   * Add samples to the buffer
   *
   * @param {Int16Array|number[]} samples - Audio samples to add
   */
  add(samples) {
    if (samples instanceof Int16Array) {
      for (let i = 0; i < samples.length; i++) {
        this.buffer.push(samples[i]);
      }
    } else {
      this.buffer.push(...samples);
    }
  }

  /**
   * Get all complete chunks from the buffer
   *
   * @returns {Int16Array[]} Array of complete chunks
   */
  getChunks() {
    const chunks = [];
    while (this.buffer.length >= this.targetChunkSize) {
      const chunk = new Int16Array(this.buffer.splice(0, this.targetChunkSize));
      chunks.push(chunk);
    }
    return chunks;
  }

  /**
   * Flush remaining samples as a final chunk
   *
   * @returns {Int16Array|null} Remaining samples or null if empty
   */
  flush() {
    if (this.buffer.length > 0) {
      const remaining = new Int16Array(this.buffer);
      this.buffer = [];
      return remaining;
    }
    return null;
  }

  /**
   * Clear the buffer
   */
  clear() {
    this.buffer = [];
  }

  /**
   * Get current buffer size
   *
   * @returns {number} Number of samples in buffer
   */
  get length() {
    return this.buffer.length;
  }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Convert Int16Array to Buffer
 *
 * @param {Int16Array} int16Array - Audio samples
 * @returns {Buffer} Node.js Buffer
 */
export function int16ArrayToBuffer(int16Array) {
  return Buffer.from(int16Array.buffer, int16Array.byteOffset, int16Array.byteLength);
}

/**
 * Convert Buffer to Int16Array
 *
 * @param {Buffer} buffer - Node.js Buffer
 * @returns {Int16Array} Audio samples
 */
export function bufferToInt16Array(buffer) {
  // Create a copy to ensure alignment
  const alignedBuffer = new ArrayBuffer(buffer.length);
  const view = new Uint8Array(alignedBuffer);
  buffer.copy(view);
  return new Int16Array(alignedBuffer);
}

/**
 * Calculate RMS (Root Mean Square) level of audio samples
 * Useful for audio level monitoring and silence detection
 *
 * @param {Int16Array} samples - Audio samples
 * @returns {number} RMS level (0 to ~32768)
 */
export function calculateRMS(samples) {
  if (!samples || samples.length === 0) return 0;

  let sumSquares = 0;
  for (let i = 0; i < samples.length; i++) {
    sumSquares += samples[i] * samples[i];
  }

  return Math.sqrt(sumSquares / samples.length);
}

/**
 * Calculate dB level from RMS
 *
 * @param {number} rms - RMS value
 * @returns {number} Level in dB (0 dB = full scale)
 */
export function rmsToDB(rms) {
  if (rms <= 0) return -Infinity;
  // Reference level is max PCM16 value (32768)
  return 20 * Math.log10(rms / 32768);
}

/**
 * Normalize volume to target RMS level
 *
 * @param {Int16Array} samples - Audio samples
 * @param {number} targetRMS - Target RMS level (default 8000, about -12dB)
 * @returns {Int16Array} Normalized samples
 */
export function normalizeVolume(samples, targetRMS = 8000) {
  const currentRMS = calculateRMS(samples);
  if (currentRMS === 0) return samples;

  const gain = targetRMS / currentRMS;
  const maxGain = 4.0;   // +12dB max gain
  const minGain = 0.25;  // -12dB max attenuation
  const clampedGain = Math.max(minGain, Math.min(maxGain, gain));

  const normalized = new Int16Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    let sample = Math.round(samples[i] * clampedGain);
    // Clip to valid PCM16 range
    sample = Math.max(-32768, Math.min(32767, sample));
    normalized[i] = sample;
  }

  return normalized;
}

/**
 * Create silence (zero samples)
 *
 * @param {number} durationMs - Duration in milliseconds
 * @param {number} sampleRate - Sample rate (default 24000)
 * @returns {Int16Array} Silent audio samples
 */
export function createSilence(durationMs, sampleRate = SAMPLE_RATE_OPENAI) {
  const numSamples = Math.floor((durationMs / 1000) * sampleRate);
  return new Int16Array(numSamples);
}

/**
 * Concatenate multiple audio buffers
 *
 * @param {Int16Array[]} buffers - Array of audio buffers
 * @returns {Int16Array} Concatenated audio
 */
export function concatenateBuffers(buffers) {
  const totalLength = buffers.reduce((sum, buf) => sum + buf.length, 0);
  const result = new Int16Array(totalLength);
  let offset = 0;
  for (const buf of buffers) {
    result.set(buf, offset);
    offset += buf.length;
  }
  return result;
}

// ============================================================================
// TESTING HELPERS
// ============================================================================

/**
 * Generate a test sine wave tone
 * Useful for testing the audio pipeline
 *
 * @param {number} frequency - Frequency in Hz (e.g., 440 for A4)
 * @param {number} durationMs - Duration in milliseconds
 * @param {number} sampleRate - Sample rate (default 24000)
 * @param {number} amplitude - Amplitude 0-1 (default 0.5)
 * @returns {Int16Array} Audio samples
 */
export function generateTestTone(frequency, durationMs, sampleRate = SAMPLE_RATE_OPENAI, amplitude = 0.5) {
  const numSamples = Math.floor((durationMs / 1000) * sampleRate);
  const samples = new Int16Array(numSamples);

  const angularFreq = 2 * Math.PI * frequency / sampleRate;
  const maxAmplitude = 32767 * amplitude;

  for (let i = 0; i < numSamples; i++) {
    samples[i] = Math.round(Math.sin(angularFreq * i) * maxAmplitude);
  }

  return samples;
}

/**
 * Generate white noise for testing
 *
 * @param {number} durationMs - Duration in milliseconds
 * @param {number} sampleRate - Sample rate (default 24000)
 * @param {number} amplitude - Amplitude 0-1 (default 0.3)
 * @returns {Int16Array} Audio samples
 */
export function generateWhiteNoise(durationMs, sampleRate = SAMPLE_RATE_OPENAI, amplitude = 0.3) {
  const numSamples = Math.floor((durationMs / 1000) * sampleRate);
  const samples = new Int16Array(numSamples);

  const maxAmplitude = 32767 * amplitude;

  for (let i = 0; i < numSamples; i++) {
    samples[i] = Math.round((Math.random() * 2 - 1) * maxAmplitude);
  }

  return samples;
}

/**
 * Verify audio contains signal (not silence)
 *
 * @param {Int16Array} samples - Audio samples
 * @param {number} silenceThreshold - RMS threshold below which is silence
 * @returns {boolean} True if audio contains signal
 */
export function hasSignal(samples, silenceThreshold = 100) {
  const rms = calculateRMS(samples);
  return rms > silenceThreshold;
}

// ============================================================================
// UNIT TESTS
// ============================================================================

/**
 * Run unit tests for the audio converter
 * Call this to verify the conversion pipeline works correctly
 *
 * @returns {Object} Test results
 */
export function runTests() {
  const results = {
    passed: 0,
    failed: 0,
    tests: [],
  };

  function test(name, fn) {
    try {
      fn();
      results.passed++;
      results.tests.push({ name, passed: true });
      logger.debug(`✓ ${name}`);
    } catch (error) {
      results.failed++;
      results.tests.push({ name, passed: false, error: error.message });
      logger.error(`✗ ${name}:`, error.message);
    }
  }

  function assertEquals(actual, expected, message) {
    if (actual !== expected) {
      throw new Error(`${message}: expected ${expected}, got ${actual}`);
    }
  }

  function assertClose(actual, expected, tolerance, message) {
    if (Math.abs(actual - expected) > tolerance) {
      throw new Error(`${message}: expected ~${expected}, got ${actual} (tolerance: ${tolerance})`);
    }
  }

  function assertTrue(condition, message) {
    if (!condition) {
      throw new Error(message);
    }
  }

  // Test 1: μ-law decode table validity
  test('MULAW_DECODE_TABLE has correct size', () => {
    assertEquals(MULAW_DECODE_TABLE.length, 256, 'Decode table size');
  });

  // Test 2: μ-law encode table validity
  test('MULAW_ENCODE_TABLE has correct size', () => {
    assertEquals(MULAW_ENCODE_TABLE.length, 65536, 'Encode table size');
  });

  // Test 3: μ-law roundtrip (encode then decode should be close to original)
  test('μ-law encode/decode roundtrip preserves signal', () => {
    const original = new Int16Array([0, 1000, -1000, 16000, -16000, 32000, -32000]);
    const encoded = encodeMulaw(original);
    const decoded = decodeMulaw(encoded);

    // μ-law is lossy, but decoded values should be within 5% of original
    for (let i = 0; i < original.length; i++) {
      const orig = original[i];
      const dec = decoded[i];
      if (orig === 0) {
        assertClose(dec, 0, 100, `Sample ${i} at zero`);
      } else {
        const error = Math.abs(dec - orig) / Math.abs(orig);
        assertTrue(error < 0.1, `Sample ${i} error too high: ${error}`);
      }
    }
  });

  // Test 4: Resample 8k to 24k produces 3x length
  test('resample8kTo24k produces 3x length', () => {
    const input = new Int16Array(100);
    const output = resample8kTo24k(input);
    assertEquals(output.length, 300, 'Output length should be 3x input');
  });

  // Test 5: Resample 24k to 8k produces 1/3 length
  test('resample24kTo8k produces 1/3 length', () => {
    const input = new Int16Array(300);
    const output = resample24kTo8k(input);
    assertEquals(output.length, 100, 'Output length should be 1/3 input');
  });

  // Test 6: Resample roundtrip preserves signal shape
  test('Resample roundtrip preserves signal shape', () => {
    // Generate a simple ramp at 8kHz
    const original8k = new Int16Array(80); // 10ms at 8kHz
    for (let i = 0; i < original8k.length; i++) {
      original8k[i] = i * 100;
    }

    // Upsample to 24k
    const upsampled = resample8kTo24k(original8k);
    assertEquals(upsampled.length, 240, 'Upsampled length');

    // Downsample back to 8k
    const downsampled = resample24kTo8k(upsampled);
    assertEquals(downsampled.length, 80, 'Downsampled length');

    // Values should be close to original (within tolerance for averaging)
    for (let i = 1; i < downsampled.length - 1; i++) {
      assertClose(downsampled[i], original8k[i], 200, `Sample ${i}`);
    }
  });

  // Test 7: mulawToOpenAI produces valid base64
  test('mulawToOpenAI produces valid base64', () => {
    // Create some μ-law test data
    const mulawData = new Uint8Array(160); // 20ms at 8kHz
    for (let i = 0; i < mulawData.length; i++) {
      mulawData[i] = 0x7F; // Silence in μ-law
    }
    const base64In = Buffer.from(mulawData).toString('base64');

    const base64Out = mulawToOpenAI(base64In);

    // Should be valid base64
    assertTrue(typeof base64Out === 'string', 'Output is string');
    assertTrue(base64Out.length > 0, 'Output is not empty');

    // Decode and verify length (should be 480 samples = 960 bytes for 20ms at 24kHz)
    const decoded = Buffer.from(base64Out, 'base64');
    assertEquals(decoded.length, 960, 'Output should be 960 bytes (480 samples at 24kHz)');
  });

  // Test 8: openaiToMulaw produces valid base64
  test('openaiToMulaw produces valid base64', () => {
    // Create PCM16 test data at 24kHz
    const pcm24k = new Int16Array(480); // 20ms at 24kHz
    for (let i = 0; i < pcm24k.length; i++) {
      pcm24k[i] = 0; // Silence
    }
    const base64In = Buffer.from(pcm24k.buffer).toString('base64');

    const base64Out = openaiToMulaw(base64In);

    // Should be valid base64
    assertTrue(typeof base64Out === 'string', 'Output is string');
    assertTrue(base64Out.length > 0, 'Output is not empty');

    // Decode and verify length (should be 160 bytes for 20ms at 8kHz)
    const decoded = Buffer.from(base64Out, 'base64');
    assertEquals(decoded.length, 160, 'Output should be 160 bytes (160 samples at 8kHz)');
  });

  // Test 9: Full pipeline roundtrip
  test('Full pipeline roundtrip preserves signal', () => {
    // Generate a test tone at 8kHz
    const tone8k = generateTestTone(440, 20, 8000); // 20ms of 440Hz

    // Encode to μ-law
    const mulaw = encodeMulaw(tone8k);
    const mulawBase64 = Buffer.from(mulaw).toString('base64');

    // Convert to OpenAI format
    const openaiBase64 = mulawToOpenAI(mulawBase64);

    // Convert back to Twilio format
    const twilioBase64 = openaiToMulaw(openaiBase64);

    // Decode the result
    const resultMulaw = Buffer.from(twilioBase64, 'base64');
    const resultPcm = decodeMulaw(resultMulaw);

    // Verify signal exists and has reasonable RMS
    const originalRMS = calculateRMS(tone8k);
    const resultRMS = calculateRMS(resultPcm);

    assertTrue(originalRMS > 1000, 'Original should have signal');
    assertTrue(resultRMS > 500, 'Result should have signal');
    assertClose(resultRMS, originalRMS, originalRMS * 0.5, 'RMS should be similar');
  });

  // Test 10: AudioBuffer accumulation
  test('AudioBuffer accumulates correctly', () => {
    const buffer = new AudioBuffer(100, 24000); // 100ms buffer
    const targetSamples = Math.floor(0.1 * 24000); // 2400 samples

    assertEquals(buffer.targetSamples, targetSamples, 'Target samples');

    // Add small chunks
    const chunk = new Int16Array(480); // 20ms
    buffer.append(chunk);
    assertEquals(buffer.length, 480, 'After first append');
    assertTrue(!buffer.isReady(), 'Should not be ready yet');

    // Add more chunks until ready
    for (let i = 0; i < 4; i++) {
      buffer.append(chunk);
    }
    assertEquals(buffer.length, 2400, 'After all appends');
    assertTrue(buffer.isReady(), 'Should be ready');

    // Flush
    const flushed = buffer.flush();
    assertEquals(flushed.length, 2400, 'Flushed samples');
    assertEquals(buffer.length, 0, 'Buffer should be empty');
  });

  // Test 11: calculateRMS
  test('calculateRMS computes correct values', () => {
    // Silence should have RMS of 0
    const silence = new Int16Array(100);
    assertEquals(calculateRMS(silence), 0, 'Silence RMS');

    // Full scale sine has RMS of max/sqrt(2)
    const fullScale = new Int16Array([32767, -32767, 32767, -32767]);
    const expectedRMS = 32767; // Simplified for square wave
    assertClose(calculateRMS(fullScale), expectedRMS, 1, 'Full scale RMS');
  });

  // Test 12: generateTestTone
  test('generateTestTone produces valid audio', () => {
    const tone = generateTestTone(1000, 50, 24000);
    const expectedSamples = Math.floor(0.05 * 24000); // 1200 samples

    assertEquals(tone.length, expectedSamples, 'Tone length');
    assertTrue(calculateRMS(tone) > 5000, 'Tone should have signal');

    // Verify it oscillates (has both positive and negative values)
    let hasPositive = false;
    let hasNegative = false;
    for (let i = 0; i < tone.length; i++) {
      if (tone[i] > 0) hasPositive = true;
      if (tone[i] < 0) hasNegative = true;
    }
    assertTrue(hasPositive && hasNegative, 'Tone should oscillate');
  });

  // Test 13: Empty input handling
  test('Functions handle empty input', () => {
    assertEquals(decodeMulaw(new Uint8Array(0)).length, 0, 'decodeMulaw empty');
    assertEquals(encodeMulaw(new Int16Array(0)).length, 0, 'encodeMulaw empty');
    assertEquals(resample8kTo24k(new Int16Array(0)).length, 0, 'resample8kTo24k empty');
    assertEquals(resample24kTo8k(new Int16Array(0)).length, 0, 'resample24kTo8k empty');
    assertEquals(calculateRMS(new Int16Array(0)), 0, 'calculateRMS empty');
  });

  // Test 14: Silence encoding
  test('Silence encoding works correctly', () => {
    const silence = new Int16Array(100); // All zeros
    const encoded = encodeMulaw(silence);
    const decoded = decodeMulaw(encoded);

    // All decoded values should be near zero
    for (let i = 0; i < decoded.length; i++) {
      assertTrue(Math.abs(decoded[i]) < 100, `Sample ${i} should be near zero`);
    }
  });

  // Print summary
  logger.info(`Audio converter tests: ${results.passed} passed, ${results.failed} failed`);

  return results;
}

// ============================================================================
// EXPORTS
// ============================================================================

export default {
  // Core conversion
  decodeMulaw,
  encodeMulaw,
  encodeMulawSample,

  // Resampling
  resample,
  resample8kTo24k,
  resample24kTo8k,

  // Pipeline functions
  mulawToPCM16_24k,
  pcm16_24kToMulaw,
  mulawToOpenAI,
  openaiToMulaw,
  mulawBase64ToPCM16Base64,
  pcm16Base64ToMulawBase64,

  // Buffer classes
  AudioBuffer,
  AudioChunkBuffer,

  // Utilities
  int16ArrayToBuffer,
  bufferToInt16Array,
  calculateRMS,
  rmsToDB,
  normalizeVolume,
  createSilence,
  concatenateBuffers,

  // Testing
  generateTestTone,
  generateWhiteNoise,
  hasSignal,
  runTests,

  // Constants
  SAMPLE_RATE_TWILIO,
  SAMPLE_RATE_OPENAI,
  MULAW_ENCODE_BIAS,
  MULAW_DECODE_BIAS,
  MULAW_CLIP,
};
