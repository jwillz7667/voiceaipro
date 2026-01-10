import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { createLogger } from '../utils/logger.js';
import { query, transaction } from '../db/pool.js';
import { optionalAuth } from '../middleware/auth.js';
import { optimizeVoicePrompt } from '../services/deepseekService.js';

const router = Router();
const logger = createLogger('routes:prompts');

// Apply optional auth to all routes - allows both authenticated and legacy device_id access
router.use(optionalAuth());

/**
 * Ensure a user exists in the database, creating them if needed
 * @param {string} deviceId - The device ID from the iOS app
 * @returns {Promise<string>} The user's UUID
 */
async function ensureUserExists(deviceId) {
  if (!deviceId) return null;

  // Try to find existing user by device_id
  const existing = await query(
    'SELECT id FROM users WHERE device_id = $1',
    [deviceId]
  );

  if (existing.rows.length > 0) {
    return existing.rows[0].id;
  }

  // Create new user - use device_id as UUID if it's valid, otherwise generate new
  const userId = uuidv4();
  const result = await query(
    `INSERT INTO users (id, device_id)
     VALUES ($1::uuid, $2)
     ON CONFLICT (device_id) DO UPDATE SET last_active = CURRENT_TIMESTAMP
     RETURNING id`,
    [userId, deviceId]
  );

  logger.info('Created new user', { userId: result.rows[0].id, deviceId });
  return result.rows[0].id;
}

router.get('/', async (req, res) => {
  try {
    const { user_id, device_id, include_default = 'true' } = req.query;

    // Priority: 1) Authenticated user, 2) device_id query param, 3) user_id query param (legacy)
    let actualUserId = null;

    if (req.user) {
      // Authenticated user - use their ID directly
      actualUserId = req.user.id;
      logger.debug('Using authenticated user ID', { userId: actualUserId });
    } else {
      // Legacy device_id lookup
      const deviceIdToLookup = device_id || user_id;
      if (deviceIdToLookup) {
        const userResult = await query(
          'SELECT id FROM users WHERE device_id = $1 OR id::text = $1',
          [deviceIdToLookup]
        );
        if (userResult.rows.length > 0) {
          actualUserId = userResult.rows[0].id;
        }
      }
    }

    let queryText = `
      SELECT id, user_id, name, instructions, voice, vad_config,
             is_default, created_at, updated_at
      FROM prompts
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    if (actualUserId) {
      if (include_default === 'true') {
        queryText += ` AND (user_id = $${paramIndex++} OR is_default = true)`;
      } else {
        queryText += ` AND user_id = $${paramIndex++}`;
      }
      params.push(actualUserId);
    } else if (!req.user && (user_id || device_id)) {
      // Legacy mode: No user found, just return defaults
      queryText += ' AND is_default = true';
    } else if (!req.user && !user_id && !device_id) {
      // No auth and no device_id - return only defaults
      queryText += ' AND is_default = true';
    }

    queryText += ' ORDER BY is_default DESC, name ASC';

    const result = await query(queryText, params);

    res.json({
      prompts: result.rows.map((row) => ({
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        instructions: row.instructions,
        voice: row.voice,
        vad_config: row.vad_config,
        is_default: row.is_default,
        created_at: row.created_at,
        updated_at: row.updated_at,
      })),
    });
  } catch (error) {
    logger.error('Failed to list prompts', error);
    res.status(500).json({
      error: {
        code: 'LIST_PROMPTS_FAILED',
        message: 'Failed to list prompts',
        details: error.message,
      },
    });
  }
});

/**
 * Optimize prompt instructions using AI
 * POST /api/prompts/optimize
 * Body: { instructions: string, model?: string }
 * Returns: { success: true, optimized_instructions: string }
 *
 * IMPORTANT: This route must be defined BEFORE /:id routes to avoid
 * "optimize" being matched as an ID parameter
 */
router.post('/optimize', async (req, res) => {
  try {
    const { instructions, model } = req.body;

    if (!instructions || typeof instructions !== 'string') {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Instructions are required and must be a string',
        },
      });
    }

    const trimmedInstructions = instructions.trim();

    if (trimmedInstructions.length < 10) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Instructions must be at least 10 characters',
        },
      });
    }

    if (trimmedInstructions.length > 10000) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Instructions must not exceed 10000 characters',
        },
      });
    }

    const optimizedInstructions = await optimizeVoicePrompt(trimmedInstructions, {
      model: model || 'deepseek-chat',
    });

    logger.info('Prompt optimized successfully', {
      originalLength: trimmedInstructions.length,
      optimizedLength: optimizedInstructions.length,
    });

    res.json({
      success: true,
      optimized_instructions: optimizedInstructions,
      original_length: trimmedInstructions.length,
      optimized_length: optimizedInstructions.length,
    });
  } catch (error) {
    logger.error('Failed to optimize prompt', error);

    // Check for specific error types
    if (error.message.includes('DEEPSEEK_API_KEY')) {
      return res.status(503).json({
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: 'Prompt optimization service is not configured',
        },
      });
    }

    if (error.message.includes('API error')) {
      return res.status(502).json({
        error: {
          code: 'UPSTREAM_ERROR',
          message: 'Failed to connect to optimization service',
        },
      });
    }

    res.status(500).json({
      error: {
        code: 'OPTIMIZE_PROMPT_FAILED',
        message: 'Failed to optimize prompt',
        details: error.message,
      },
    });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      `SELECT id, user_id, name, instructions, voice, vad_config,
              is_default, created_at, updated_at
       FROM prompts
       WHERE id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'PROMPT_NOT_FOUND',
          message: `Prompt not found: ${id}`,
        },
      });
    }

    const row = result.rows[0];
    res.json({
      prompt: {
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        instructions: row.instructions,
        voice: row.voice,
        vad_config: row.vad_config,
        is_default: row.is_default,
        created_at: row.created_at,
        updated_at: row.updated_at,
      },
    });
  } catch (error) {
    logger.error('Failed to get prompt', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'GET_PROMPT_FAILED',
        message: 'Failed to retrieve prompt',
        details: error.message,
      },
    });
  }
});

router.post('/', async (req, res) => {
  try {
    const {
      user_id,
      device_id,
      name,
      instructions,
      voice = 'marin',
      vad_config,
      is_default = false,
    } = req.body;

    if (!name || !instructions) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Name and instructions are required',
        },
      });
    }

    // Priority: 1) Authenticated user, 2) device_id/user_id from body
    let validUserId = null;
    if (req.user) {
      validUserId = req.user.id;
    } else {
      const deviceIdToUse = device_id || user_id;
      validUserId = deviceIdToUse ? await ensureUserExists(deviceIdToUse) : null;
    }

    const id = uuidv4();

    const result = await query(
      `INSERT INTO prompts (id, user_id, name, instructions, voice, vad_config, is_default)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
      [id, validUserId, name, instructions, voice, vad_config || null, is_default]
    );

    const row = result.rows[0];

    logger.info('Prompt created', { id: row.id, name: row.name, userId: user_id });

    res.status(201).json({
      prompt: {
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        instructions: row.instructions,
        voice: row.voice,
        vad_config: row.vad_config,
        is_default: row.is_default,
        created_at: row.created_at,
        updated_at: row.updated_at,
      },
    });
  } catch (error) {
    logger.error('Failed to create prompt', error);
    res.status(500).json({
      error: {
        code: 'CREATE_PROMPT_FAILED',
        message: 'Failed to create prompt',
        details: error.message,
      },
    });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const {
      name,
      instructions,
      voice,
      vad_config,
      is_default,
    } = req.body;

    const existing = await query('SELECT id FROM prompts WHERE id = $1', [id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'PROMPT_NOT_FOUND',
          message: `Prompt not found: ${id}`,
        },
      });
    }

    const updates = [];
    const params = [];
    let paramIndex = 1;

    if (name !== undefined) {
      updates.push(`name = $${paramIndex++}`);
      params.push(name);
    }

    if (instructions !== undefined) {
      updates.push(`instructions = $${paramIndex++}`);
      params.push(instructions);
    }

    if (voice !== undefined) {
      updates.push(`voice = $${paramIndex++}`);
      params.push(voice);
    }

    if (vad_config !== undefined) {
      updates.push(`vad_config = $${paramIndex++}`);
      params.push(vad_config);
    }

    if (is_default !== undefined) {
      updates.push(`is_default = $${paramIndex++}`);
      params.push(is_default);
    }

    if (updates.length === 0) {
      return res.status(400).json({
        error: {
          code: 'NO_UPDATES',
          message: 'No fields to update',
        },
      });
    }

    updates.push('updated_at = CURRENT_TIMESTAMP');
    params.push(id);

    const result = await query(
      `UPDATE prompts SET ${updates.join(', ')}
       WHERE id = $${paramIndex}
       RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
      params
    );

    const row = result.rows[0];

    logger.info('Prompt updated', { id: row.id, name: row.name });

    res.json({
      prompt: {
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        instructions: row.instructions,
        voice: row.voice,
        vad_config: row.vad_config,
        is_default: row.is_default,
        created_at: row.created_at,
        updated_at: row.updated_at,
      },
    });
  } catch (error) {
    logger.error('Failed to update prompt', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'UPDATE_PROMPT_FAILED',
        message: 'Failed to update prompt',
        details: error.message,
      },
    });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query('DELETE FROM prompts WHERE id = $1 RETURNING id, name', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'PROMPT_NOT_FOUND',
          message: `Prompt not found: ${id}`,
        },
      });
    }

    logger.info('Prompt deleted', { id, name: result.rows[0].name });

    res.json({
      success: true,
      deleted_id: id,
    });
  } catch (error) {
    logger.error('Failed to delete prompt', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'DELETE_PROMPT_FAILED',
        message: 'Failed to delete prompt',
        details: error.message,
      },
    });
  }
});

router.post('/:id/default', async (req, res) => {
  try {
    const { id } = req.params;
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'user_id is required',
        },
      });
    }

    // Clear existing user defaults and set new one
    await transaction(async (client) => {
      // Clear existing defaults for this user
      await client.query(
        'UPDATE prompts SET is_default = false, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND is_default = true',
        [user_id]
      );

      // Set new default
      const result = await client.query(
        `UPDATE prompts SET is_default = true, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1 AND (user_id = $2 OR user_id IS NULL)
         RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
        [id, user_id]
      );

      if (result.rows.length === 0) {
        throw new Error('PROMPT_NOT_FOUND');
      }

      return result.rows[0];
    }).then((row) => {
      logger.info('Default prompt set', { promptId: id, userId: user_id });

      res.json({
        success: true,
        prompt: {
          id: row.id,
          user_id: row.user_id,
          name: row.name,
          instructions: row.instructions,
          voice: row.voice,
          vad_config: row.vad_config,
          is_default: row.is_default,
          created_at: row.created_at,
          updated_at: row.updated_at,
        },
      });
    }).catch((error) => {
      if (error.message === 'PROMPT_NOT_FOUND') {
        return res.status(404).json({
          error: {
            code: 'PROMPT_NOT_FOUND',
            message: `Prompt not found or not accessible: ${id}`,
          },
        });
      }
      throw error;
    });
  } catch (error) {
    logger.error('Failed to set default prompt', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'SET_DEFAULT_FAILED',
        message: 'Failed to set default prompt',
        details: error.message,
      },
    });
  }
});

router.post('/:id/duplicate', async (req, res) => {
  try {
    const { id } = req.params;
    const { name: newName, user_id } = req.body;

    const original = await query(
      'SELECT name, instructions, voice, vad_config FROM prompts WHERE id = $1',
      [id]
    );

    if (original.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'PROMPT_NOT_FOUND',
          message: `Prompt not found: ${id}`,
        },
      });
    }

    const { name, instructions, voice, vad_config } = original.rows[0];
    const duplicateName = newName || `${name} (Copy)`;
    const newId = uuidv4();

    const result = await query(
      `INSERT INTO prompts (id, user_id, name, instructions, voice, vad_config, is_default)
       VALUES ($1, $2, $3, $4, $5, $6, false)
       RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
      [newId, user_id || null, duplicateName, instructions, voice, vad_config]
    );

    const row = result.rows[0];

    logger.info('Prompt duplicated', { originalId: id, newId: row.id, name: row.name });

    res.status(201).json({
      prompt: {
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        instructions: row.instructions,
        voice: row.voice,
        vad_config: row.vad_config,
        is_default: row.is_default,
        created_at: row.created_at,
        updated_at: row.updated_at,
      },
    });
  } catch (error) {
    logger.error('Failed to duplicate prompt', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'DUPLICATE_PROMPT_FAILED',
        message: 'Failed to duplicate prompt',
        details: error.message,
      },
    });
  }
});

export default router;
