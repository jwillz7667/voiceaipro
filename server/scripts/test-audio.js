#!/usr/bin/env node
/**
 * Audio Converter Test Runner
 *
 * Run with: node scripts/test-audio.js
 */

import { runTests, generateTestTone, mulawToOpenAI, openaiToMulaw, calculateRMS } from '../src/audio/converter.js';

console.log('='.repeat(60));
console.log('VoiceAI Pro - Audio Converter Test Suite');
console.log('='.repeat(60));
console.log();

// Run unit tests
const results = runTests();

console.log();
console.log('='.repeat(60));
console.log('RESULTS');
console.log('='.repeat(60));
console.log(`Total:  ${results.tests.length}`);
console.log(`Passed: ${results.passed}`);
console.log(`Failed: ${results.failed}`);
console.log();

if (results.failed > 0) {
  console.log('Failed tests:');
  results.tests.filter(t => !t.passed).forEach(t => {
    console.log(`  ✗ ${t.name}`);
    console.log(`    ${t.error}`);
  });
  console.log();
}

// Run an end-to-end demo
console.log('='.repeat(60));
console.log('END-TO-END DEMO');
console.log('='.repeat(60));
console.log();

// Generate a 100ms 440Hz tone at 8kHz (simulating Twilio input)
const tone8k = generateTestTone(440, 100, 8000);
console.log(`Generated 100ms 440Hz tone at 8kHz: ${tone8k.length} samples`);
console.log(`  RMS level: ${calculateRMS(tone8k).toFixed(1)}`);

// Simulate the Twilio → OpenAI → Twilio roundtrip
import { encodeMulaw, decodeMulaw } from '../src/audio/converter.js';

// Encode to μ-law (what Twilio sends)
const mulaw = encodeMulaw(tone8k);
const mulawBase64 = Buffer.from(mulaw).toString('base64');
console.log(`\nEncoded to μ-law: ${mulaw.length} bytes`);
console.log(`  Base64 length: ${mulawBase64.length} chars`);

// Convert to OpenAI format (24kHz PCM16)
const openaiBase64 = mulawToOpenAI(mulawBase64);
const openaiPcm = Buffer.from(openaiBase64, 'base64');
console.log(`\nConverted to OpenAI format: ${openaiPcm.length} bytes (${openaiPcm.length / 2} samples at 24kHz)`);

// Convert back to Twilio format (8kHz μ-law)
const twilioBase64 = openaiToMulaw(openaiBase64);
const twilioMulaw = Buffer.from(twilioBase64, 'base64');
console.log(`\nConverted back to Twilio format: ${twilioMulaw.length} bytes`);

// Decode final result
const finalPcm = decodeMulaw(twilioMulaw);
const finalRMS = calculateRMS(finalPcm);
console.log(`\nFinal decoded PCM: ${finalPcm.length} samples`);
console.log(`  RMS level: ${finalRMS.toFixed(1)}`);

// Calculate signal preservation
const originalRMS = calculateRMS(tone8k);
const preservation = (finalRMS / originalRMS * 100).toFixed(1);
console.log(`\nSignal preservation: ${preservation}%`);

console.log();
console.log('='.repeat(60));
if (results.failed === 0) {
  console.log('All tests passed!');
  process.exit(0);
} else {
  console.log(`${results.failed} test(s) failed!`);
  process.exit(1);
}
