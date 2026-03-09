import { createLogger } from '../utils/logger.js';

const logger = createLogger('openai-service');

/**
 * Build session config in GA nested format for gpt-realtime-1.5
 */
export function buildSessionConfig(options = {}) {
  const {
    instructions = 'You are a helpful AI assistant. Respond naturally and conversationally.',
    voice = 'marin',
    voiceSpeed = 1.0,
    vadType = 'semantic_vad',
    vadConfig = {},
    noiseReduction = null,
    transcriptionModel = 'gpt-4o-transcribe',
    tools = [],
  } = options;

  const sessionConfig = {
    type: 'realtime',
    instructions,
    output_modalities: ['audio'],
    audio: {
      input: {},
      output: {},
    },
  };

  // Audio input: transcription
  if (transcriptionModel) {
    sessionConfig.audio.input.transcription = {
      model: transcriptionModel,
    };
  }

  // Audio input: noise reduction
  if (noiseReduction) {
    sessionConfig.audio.input.noise_reduction = { type: noiseReduction };
  }

  // Audio input: turn detection / VAD
  if (vadType === 'server_vad') {
    const turnDetection = {
      type: 'server_vad',
      threshold: vadConfig.threshold ?? 0.5,
      prefix_padding_ms: vadConfig.prefixPaddingMs ?? 300,
      silence_duration_ms: vadConfig.silenceDurationMs ?? 500,
      create_response: vadConfig.createResponse ?? true,
    };
    if (vadConfig.idleTimeoutMs) {
      turnDetection.idle_timeout_ms = vadConfig.idleTimeoutMs;
    }
    sessionConfig.audio.input.turn_detection = turnDetection;
  } else if (vadType === 'semantic_vad') {
    sessionConfig.audio.input.turn_detection = {
      type: 'semantic_vad',
      eagerness: vadConfig.eagerness ?? 'high',
      create_response: vadConfig.createResponse ?? true,
    };
  } else if (vadType === 'disabled') {
    sessionConfig.audio.input.turn_detection = null;
  }

  // Audio output: voice
  sessionConfig.audio.output.voice = voice;

  // Audio output: speed
  if (voiceSpeed !== 1.0) {
    sessionConfig.audio.output.speed = voiceSpeed;
  }

  if (tools && tools.length > 0) {
    sessionConfig.tools = tools;
    sessionConfig.tool_choice = 'auto';
  }

  return sessionConfig;
}

export function buildSessionUpdateEvent(config) {
  return {
    type: 'session.update',
    session: buildSessionConfig(config),
  };
}

export function buildAudioAppendEvent(audioBase64) {
  return {
    type: 'input_audio_buffer.append',
    audio: audioBase64,
  };
}

export function buildAudioCommitEvent() {
  return {
    type: 'input_audio_buffer.commit',
  };
}

export function buildAudioClearEvent() {
  return {
    type: 'input_audio_buffer.clear',
  };
}

export function buildResponseCreateEvent(options = {}) {
  const event = {
    type: 'response.create',
  };

  if (options.instructions) {
    event.response = {
      instructions: options.instructions,
    };
  }

  return event;
}

export function buildResponseCancelEvent() {
  return {
    type: 'response.cancel',
  };
}

export function buildConversationItemCreateEvent(content, role = 'user') {
  return {
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role,
      content: [
        {
          type: 'input_text',
          text: content,
        },
      ],
    },
  };
}

export function buildFunctionResultEvent(callId, result) {
  return {
    type: 'conversation.item.create',
    item: {
      type: 'function_call_output',
      call_id: callId,
      output: typeof result === 'string' ? result : JSON.stringify(result),
    },
  };
}

export function buildTruncateEvent(itemId, contentIndex, audioEndMs) {
  return {
    type: 'conversation.item.truncate',
    item_id: itemId,
    content_index: contentIndex,
    audio_end_ms: audioEndMs,
  };
}

export function parseOpenAIEvent(eventData) {
  try {
    const event = typeof eventData === 'string' ? JSON.parse(eventData) : eventData;

    const parsed = {
      type: event.type,
      raw: event,
    };

    switch (event.type) {
      case 'session.created':
        parsed.sessionId = event.session?.id;
        parsed.model = event.session?.model;
        break;

      case 'session.updated':
        parsed.session = event.session;
        break;

      case 'input_audio_buffer.speech_started':
        parsed.audioStartMs = event.audio_start_ms;
        parsed.itemId = event.item_id;
        break;

      case 'input_audio_buffer.speech_stopped':
        parsed.audioEndMs = event.audio_end_ms;
        parsed.itemId = event.item_id;
        break;

      case 'conversation.item.input_audio_transcription.completed':
        parsed.transcript = event.transcript;
        parsed.itemId = event.item_id;
        break;

      case 'response.created':
        parsed.responseId = event.response?.id;
        parsed.status = event.response?.status;
        break;

      case 'response.output_audio.delta':
        parsed.audio = event.delta;
        parsed.responseId = event.response_id;
        parsed.itemId = event.item_id;
        break;

      case 'response.output_audio_transcript.delta':
        parsed.transcript = event.delta;
        parsed.responseId = event.response_id;
        break;

      case 'response.output_audio_transcript.done':
        parsed.transcript = event.transcript;
        parsed.responseId = event.response_id;
        break;

      case 'response.done':
        parsed.responseId = event.response?.id;
        parsed.status = event.response?.status;
        parsed.usage = event.response?.usage;
        break;

      case 'response.function_call_arguments.done':
        parsed.callId = event.call_id;
        parsed.name = event.name;
        parsed.arguments = event.arguments;
        break;

      case 'error':
        parsed.error = {
          type: event.error?.type,
          code: event.error?.code,
          message: event.error?.message,
          param: event.error?.param,
        };
        break;

      case 'rate_limits.updated':
        parsed.rateLimits = event.rate_limits;
        break;
    }

    return parsed;
  } catch (error) {
    logger.error('Failed to parse OpenAI event', { error: error.message });
    return null;
  }
}

export const AVAILABLE_VOICES = [
  { id: 'marin', name: 'Marin', description: 'Professional, clear', recommended: 'Assistants' },
  { id: 'cedar', name: 'Cedar', description: 'Natural, conversational', recommended: 'Support agents' },
  { id: 'alloy', name: 'Alloy', description: 'Neutral, balanced', recommended: 'General purpose' },
  { id: 'echo', name: 'Echo', description: 'Warm, engaging', recommended: 'Customer service' },
  { id: 'shimmer', name: 'Shimmer', description: 'Energetic, expressive', recommended: 'Sales' },
  { id: 'ash', name: 'Ash', description: 'Confident, assertive', recommended: 'Business' },
  { id: 'ballad', name: 'Ballad', description: 'Storytelling tone', recommended: 'Narratives' },
  { id: 'coral', name: 'Coral', description: 'Friendly, approachable', recommended: 'Casual' },
  { id: 'sage', name: 'Sage', description: 'Wise, thoughtful', recommended: 'Advisory' },
  { id: 'verse', name: 'Verse', description: 'Dramatic, expressive', recommended: 'Creative' },
];

export const AVAILABLE_MODELS = [
  { id: 'gpt-realtime-1.5', name: 'GPT Realtime 1.5', description: 'Full capability realtime model' },
  { id: 'gpt-realtime-1.5-mini', name: 'GPT Realtime 1.5 Mini', description: 'Faster, more cost-effective' },
];

export const VAD_TYPES = [
  { id: 'server_vad', name: 'Server VAD', description: 'Traditional voice activity detection' },
  { id: 'semantic_vad', name: 'Semantic VAD', description: 'Context-aware turn detection' },
  { id: 'disabled', name: 'Disabled', description: 'Manual push-to-talk mode' },
];

export const TRANSCRIPTION_MODELS = [
  { id: 'gpt-4o-transcribe', name: 'GPT-4o Transcribe', description: 'Enhanced accuracy (Recommended)' },
  { id: 'gpt-4o-mini-transcribe', name: 'GPT-4o Mini Transcribe', description: 'Faster, cost-effective' },
];

export const NOISE_REDUCTION_TYPES = [
  { id: null, name: 'Off', description: 'No noise reduction' },
  { id: 'near_field', name: 'Near Field', description: 'For close microphones' },
  { id: 'far_field', name: 'Far Field', description: 'For distant microphones' },
];

export default {
  buildSessionConfig,
  buildSessionUpdateEvent,
  buildAudioAppendEvent,
  buildAudioCommitEvent,
  buildAudioClearEvent,
  buildResponseCreateEvent,
  buildResponseCancelEvent,
  buildConversationItemCreateEvent,
  buildFunctionResultEvent,
  buildTruncateEvent,
  parseOpenAIEvent,
  AVAILABLE_VOICES,
  AVAILABLE_MODELS,
  VAD_TYPES,
  TRANSCRIPTION_MODELS,
  NOISE_REDUCTION_TYPES,
};
