-- VoiceAI Bridge Server - Initial Database Schema
-- Migration: 001_initial_schema
-- Created: 2025-12-31

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE users IS 'Stores user/device identities';
COMMENT ON COLUMN users.device_id IS 'Unique device identifier from iOS app';

-- Prompts table (created before call_sessions due to foreign key)
CREATE TABLE IF NOT EXISTS prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    instructions TEXT NOT NULL,
    voice VARCHAR(50) DEFAULT 'marin',
    vad_config JSONB,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE prompts IS 'Saved AI prompt configurations';
COMMENT ON COLUMN prompts.instructions IS 'System instructions for the AI assistant';
COMMENT ON COLUMN prompts.vad_config IS 'Voice Activity Detection configuration (JSON)';

-- Call sessions table
CREATE TABLE IF NOT EXISTS call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    call_sid VARCHAR(255) UNIQUE,
    direction VARCHAR(20) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    phone_number VARCHAR(50),
    status VARCHAR(50) NOT NULL DEFAULT 'initializing',
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER,
    prompt_id UUID REFERENCES prompts(id) ON DELETE SET NULL,
    config_snapshot JSONB
);

COMMENT ON TABLE call_sessions IS 'Call session records';
COMMENT ON COLUMN call_sessions.call_sid IS 'Twilio Call SID';
COMMENT ON COLUMN call_sessions.config_snapshot IS 'Configuration used for this call';

-- Call events log table
CREATE TABLE IF NOT EXISTS call_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    direction VARCHAR(20) NOT NULL CHECK (direction IN ('incoming', 'outgoing')),
    payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE call_events IS 'Real-time event log for calls';
COMMENT ON COLUMN call_events.direction IS 'incoming = from OpenAI/Twilio, outgoing = to OpenAI/Twilio';

-- Recordings table
CREATE TABLE IF NOT EXISTS recordings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    storage_path VARCHAR(500) NOT NULL,
    duration_seconds INTEGER,
    file_size_bytes BIGINT,
    format VARCHAR(20) DEFAULT 'wav',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE recordings IS 'Call recording metadata';
COMMENT ON COLUMN recordings.storage_path IS 'File system path or S3 key for recording';

-- Transcripts table
CREATE TABLE IF NOT EXISTS transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_session_id UUID NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    speaker VARCHAR(20) NOT NULL CHECK (speaker IN ('user', 'assistant')),
    content TEXT NOT NULL,
    timestamp_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE transcripts IS 'Call transcription segments';
COMMENT ON COLUMN transcripts.timestamp_ms IS 'Milliseconds from call start';

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_users_device ON users(device_id);
CREATE INDEX IF NOT EXISTS idx_users_last_active ON users(last_active);

CREATE INDEX IF NOT EXISTS idx_call_sessions_user ON call_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_call_sessions_call_sid ON call_sessions(call_sid);
CREATE INDEX IF NOT EXISTS idx_call_sessions_status ON call_sessions(status);
CREATE INDEX IF NOT EXISTS idx_call_sessions_started ON call_sessions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_sessions_direction ON call_sessions(direction);

CREATE INDEX IF NOT EXISTS idx_call_events_session ON call_events(call_session_id);
CREATE INDEX IF NOT EXISTS idx_call_events_type ON call_events(event_type);
CREATE INDEX IF NOT EXISTS idx_call_events_created ON call_events(created_at);

CREATE INDEX IF NOT EXISTS idx_recordings_session ON recordings(call_session_id);
CREATE INDEX IF NOT EXISTS idx_recordings_created ON recordings(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_transcripts_session ON transcripts(call_session_id);
CREATE INDEX IF NOT EXISTS idx_transcripts_speaker ON transcripts(speaker);
CREATE INDEX IF NOT EXISTS idx_transcripts_timestamp ON transcripts(timestamp_ms);

CREATE INDEX IF NOT EXISTS idx_prompts_user ON prompts(user_id);
CREATE INDEX IF NOT EXISTS idx_prompts_default ON prompts(is_default) WHERE is_default = TRUE;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for prompts updated_at
DROP TRIGGER IF EXISTS update_prompts_updated_at ON prompts;
CREATE TRIGGER update_prompts_updated_at
    BEFORE UPDATE ON prompts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert default prompts
INSERT INTO prompts (id, name, instructions, voice, vad_config, is_default)
VALUES
    (
        gen_random_uuid(),
        'General Assistant',
        'You are a helpful AI assistant conducting a phone conversation. Be natural, conversational, and helpful. Keep responses concise as this is a voice call. Ask clarifying questions when needed.',
        'marin',
        '{"type": "server_vad", "threshold": 0.5, "prefixPaddingMs": 300, "silenceDurationMs": 500, "createResponse": true}'::jsonb,
        true
    ),
    (
        gen_random_uuid(),
        'Customer Support',
        'You are a friendly customer support agent. Listen carefully to the caller''s concerns, express empathy, and provide helpful solutions. Always confirm you understand the issue before offering solutions.',
        'cedar',
        '{"type": "server_vad", "threshold": 0.5, "prefixPaddingMs": 300, "silenceDurationMs": 600, "createResponse": true}'::jsonb,
        false
    ),
    (
        gen_random_uuid(),
        'Appointment Scheduler',
        'You are an appointment scheduling assistant. Help callers schedule, reschedule, or cancel appointments. Confirm all details including date, time, and purpose of the appointment.',
        'coral',
        '{"type": "semantic_vad", "eagerness": "medium", "createResponse": true}'::jsonb,
        false
    )
ON CONFLICT DO NOTHING;

-- Grant permissions (adjust role name as needed for Railway)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO voiceai_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO voiceai_user;
