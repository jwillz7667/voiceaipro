import { query } from '../db/pool.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('prompt-service');

/**
 * Load prompt configuration from database by promptId
 * Returns the config object with instructions, voice, and vadConfig
 *
 * @param {string} promptId - The prompt UUID
 * @returns {Object|null} - Config object or null if not found
 */
export async function loadPromptConfig(promptId) {
  if (!promptId) {
    return null;
  }

  try {
    const result = await query(
      `SELECT id, name, instructions, voice, vad_config
       FROM prompts
       WHERE id = $1`,
      [promptId]
    );

    if (result.rows.length === 0) {
      logger.warn('Prompt not found', { promptId });
      return null;
    }

    const prompt = result.rows[0];

    logger.info('Loaded prompt config', {
      promptId,
      name: prompt.name,
      instructionsLength: prompt.instructions?.length || 0,
      voice: prompt.voice,
      hasVadConfig: !!prompt.vad_config,
    });

    // Build config object from prompt
    const config = {};

    if (prompt.instructions) {
      config.instructions = prompt.instructions;
    }

    if (prompt.voice) {
      config.voice = prompt.voice;
    }

    if (prompt.vad_config) {
      // vad_config is stored as JSONB, parse if needed
      const vadConfig = typeof prompt.vad_config === 'string'
        ? JSON.parse(prompt.vad_config)
        : prompt.vad_config;

      if (vadConfig.type) {
        config.vadType = vadConfig.type;
      }
      if (vadConfig.eagerness || vadConfig.createResponse !== undefined || vadConfig.interruptResponse !== undefined) {
        config.vadConfig = {
          eagerness: vadConfig.eagerness,
          createResponse: vadConfig.createResponse,
          interruptResponse: vadConfig.interruptResponse,
        };
      }
    }

    return config;
  } catch (error) {
    logger.error('Failed to load prompt config', {
      promptId,
      error: error.message,
    });
    return null;
  }
}

/**
 * Get default prompt for a user or global default
 *
 * @param {string} userId - Optional user ID
 * @returns {Object|null} - Config object or null if not found
 */
export async function getDefaultPromptConfig(userId = null) {
  try {
    let result;

    if (userId) {
      // Try user's default first
      result = await query(
        `SELECT id, name, instructions, voice, vad_config
         FROM prompts
         WHERE user_id = $1 AND is_default = true
         LIMIT 1`,
        [userId]
      );
    }

    // Fall back to global default
    if (!result || result.rows.length === 0) {
      result = await query(
        `SELECT id, name, instructions, voice, vad_config
         FROM prompts
         WHERE user_id IS NULL AND is_default = true
         LIMIT 1`
      );
    }

    if (result.rows.length === 0) {
      return null;
    }

    const prompt = result.rows[0];

    logger.info('Loaded default prompt config', {
      promptId: prompt.id,
      name: prompt.name,
      userId,
    });

    const config = {};

    if (prompt.instructions) {
      config.instructions = prompt.instructions;
    }

    if (prompt.voice) {
      config.voice = prompt.voice;
    }

    if (prompt.vad_config) {
      const vadConfig = typeof prompt.vad_config === 'string'
        ? JSON.parse(prompt.vad_config)
        : prompt.vad_config;

      if (vadConfig.type) {
        config.vadType = vadConfig.type;
      }
      if (vadConfig.eagerness || vadConfig.createResponse !== undefined || vadConfig.interruptResponse !== undefined) {
        config.vadConfig = {
          eagerness: vadConfig.eagerness,
          createResponse: vadConfig.createResponse,
          interruptResponse: vadConfig.interruptResponse,
        };
      }
    }

    return config;
  } catch (error) {
    logger.error('Failed to load default prompt config', {
      userId,
      error: error.message,
    });
    return null;
  }
}

export default {
  loadPromptConfig,
  getDefaultPromptConfig,
};
