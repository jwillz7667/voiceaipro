/**
 * Database Queries - Main Export
 *
 * Re-exports all query modules for convenient imports
 */

export * as calls from './calls.js';
export * as recordings from './recordings.js';
export * as prompts from './prompts.js';
export * as transcripts from './transcripts.js';
export * as users from './users.js';

// Also export individual modules as defaults
export { default as callQueries } from './calls.js';
export { default as recordingQueries } from './recordings.js';
export { default as promptQueries } from './prompts.js';
export { default as transcriptQueries } from './transcripts.js';
export { default as userQueries } from './users.js';
