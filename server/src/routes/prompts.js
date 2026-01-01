import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { createLogger } from '../utils/logger.js';
import { query, transaction } from '../db/pool.js';

const router = Router();
const logger = createLogger('routes:prompts');

router.get('/', async (req, res) => {
  try {
    const { user_id, include_default = 'true' } = req.query;

    let queryText = `
      SELECT id, user_id, name, instructions, voice, vad_config,
             is_default, created_at, updated_at
      FROM prompts
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    if (user_id) {
      if (include_default === 'true') {
        queryText += ` AND (user_id = $${paramIndex++} OR is_default = true)`;
      } else {
        queryText += ` AND user_id = $${paramIndex++}`;
      }
      params.push(user_id);
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

    const id = uuidv4();

    const result = await query(
      `INSERT INTO prompts (id, user_id, name, instructions, voice, vad_config, is_default)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
      [id, user_id || null, name, instructions, voice, vad_config || null, is_default]
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
