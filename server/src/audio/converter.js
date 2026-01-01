import { createLogger } from '../utils/logger.js';

const logger = createLogger('audio');

const MULAW_BIAS = 0x84;
const MULAW_MAX = 0x7FFF;
const MULAW_CLIP = 32635;

const MULAW_DECODE_TABLE = new Int16Array(256);
const MULAW_ENCODE_TABLE = new Uint8Array(65536);

(function initializeTables() {
  for (let i = 0; i < 256; i++) {
    let mulaw = ~i;
    let sign = mulaw & 0x80;
    let exponent = (mulaw >> 4) & 0x07;
    let mantissa = mulaw & 0x0F;
    let sample = ((mantissa << 3) + MULAW_BIAS) << exponent;
    sample -= MULAW_BIAS;
    MULAW_DECODE_TABLE[i] = sign ? -sample : sample;
  }

  for (let i = 0; i < 65536; i++) {
    let sample = i - 32768;
    let sign = 0;
    if (sample < 0) {
      sign = 0x80;
      sample = -sample;
    }
    if (sample > MULAW_CLIP) sample = MULAW_CLIP;
    sample += MULAW_BIAS;

    let exponent = 7;
    for (let expMask = 0x4000; (sample & expMask) === 0 && exponent > 0; exponent--, expMask >>= 1);

    let mantissa = (sample >> (exponent + 3)) & 0x0F;
    let mulawByte = ~(sign | (exponent << 4) | mantissa) & 0xFF;
    MULAW_ENCODE_TABLE[i] = mulawByte;
  }

  logger.debug('Audio conversion tables initialized');
})();

export function decodeMulaw(mulawBuffer) {
  const samples = new Int16Array(mulawBuffer.length);
  for (let i = 0; i < mulawBuffer.length; i++) {
    samples[i] = MULAW_DECODE_TABLE[mulawBuffer[i]];
  }
  return samples;
}

export function encodeMulaw(pcmBuffer) {
  const mulaw = new Uint8Array(pcmBuffer.length);
  for (let i = 0; i < pcmBuffer.length; i++) {
    const sample = pcmBuffer[i] + 32768;
    mulaw[i] = MULAW_ENCODE_TABLE[sample];
  }
  return mulaw;
}

export function resample(inputSamples, inputRate, outputRate) {
  if (inputRate === outputRate) {
    return inputSamples;
  }

  const ratio = inputRate / outputRate;
  const outputLength = Math.floor(inputSamples.length / ratio);
  const output = new Int16Array(outputLength);

  if (outputRate > inputRate) {
    for (let i = 0; i < outputLength; i++) {
      const srcPos = i * ratio;
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
  } else {
    for (let i = 0; i < outputLength; i++) {
      const srcPos = i * ratio;
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
  }

  return output;
}

export function mulawToPCM16_24k(mulawBuffer) {
  const pcm8k = decodeMulaw(mulawBuffer);
  const pcm24k = resample(pcm8k, 8000, 24000);
  return pcm24k;
}

export function pcm16_24kToMulaw(pcm24kBuffer) {
  const pcm8k = resample(pcm24kBuffer, 24000, 8000);
  const mulaw = encodeMulaw(pcm8k);
  return mulaw;
}

export function mulawBase64ToPCM16Base64(mulawBase64) {
  const mulawBuffer = Buffer.from(mulawBase64, 'base64');
  const mulawUint8 = new Uint8Array(mulawBuffer);
  const pcm24k = mulawToPCM16_24k(mulawUint8);
  const pcm24kBuffer = Buffer.from(pcm24k.buffer);
  return pcm24kBuffer.toString('base64');
}

export function pcm16Base64ToMulawBase64(pcm16Base64) {
  const pcm16Buffer = Buffer.from(pcm16Base64, 'base64');
  const pcm16Array = new Int16Array(
    pcm16Buffer.buffer,
    pcm16Buffer.byteOffset,
    pcm16Buffer.length / 2
  );
  const mulaw = pcm16_24kToMulaw(pcm16Array);
  return Buffer.from(mulaw).toString('base64');
}

export function int16ArrayToBuffer(int16Array) {
  return Buffer.from(int16Array.buffer, int16Array.byteOffset, int16Array.byteLength);
}

export function bufferToInt16Array(buffer) {
  const arrayBuffer = buffer.buffer.slice(
    buffer.byteOffset,
    buffer.byteOffset + buffer.byteLength
  );
  return new Int16Array(arrayBuffer);
}

export function calculateRMS(samples) {
  if (samples.length === 0) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) {
    sum += samples[i] * samples[i];
  }
  return Math.sqrt(sum / samples.length);
}

export function normalizeVolume(samples, targetRMS = 8000) {
  const currentRMS = calculateRMS(samples);
  if (currentRMS === 0) return samples;

  const gain = targetRMS / currentRMS;
  const maxGain = 4.0;
  const minGain = 0.25;
  const clampedGain = Math.max(minGain, Math.min(maxGain, gain));

  const normalized = new Int16Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    let sample = Math.round(samples[i] * clampedGain);
    sample = Math.max(-32768, Math.min(32767, sample));
    normalized[i] = sample;
  }

  return normalized;
}

export function createSilence(durationMs, sampleRate) {
  const numSamples = Math.floor((durationMs / 1000) * sampleRate);
  return new Int16Array(numSamples);
}

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

class AudioChunkBuffer {
  constructor(targetChunkSize = 960) {
    this.buffer = [];
    this.targetChunkSize = targetChunkSize;
  }

  add(samples) {
    this.buffer.push(...samples);
  }

  getChunks() {
    const chunks = [];
    while (this.buffer.length >= this.targetChunkSize) {
      const chunk = new Int16Array(this.buffer.splice(0, this.targetChunkSize));
      chunks.push(chunk);
    }
    return chunks;
  }

  flush() {
    if (this.buffer.length > 0) {
      const remaining = new Int16Array(this.buffer);
      this.buffer = [];
      return remaining;
    }
    return null;
  }

  clear() {
    this.buffer = [];
  }

  get length() {
    return this.buffer.length;
  }
}

export { AudioChunkBuffer };

export default {
  decodeMulaw,
  encodeMulaw,
  resample,
  mulawToPCM16_24k,
  pcm16_24kToMulaw,
  mulawBase64ToPCM16Base64,
  pcm16Base64ToMulawBase64,
  int16ArrayToBuffer,
  bufferToInt16Array,
  calculateRMS,
  normalizeVolume,
  createSilence,
  concatenateBuffers,
  AudioChunkBuffer,
};
