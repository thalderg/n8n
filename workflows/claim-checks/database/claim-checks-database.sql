-- Claim Checks: the story archive and the bot's conversations (Postgres).
-- The same tables, keys and indexes as the running system (copied from its database on 2026-11-06).
-- Run it once in the database your n8n Postgres credential uses. Safe to read; it stops at the first error.
--
-- Docker example (container n8n-postgres, database n8n_memory):
--   docker exec -i n8n-postgres psql -U "$POSTGRES_USER" -d n8n_memory -v ON_ERROR_STOP=1 < claim-checks-database.sql
-- Then give the read-only login a password (hidden prompt):
--   docker exec -it n8n-postgres psql -U "$POSTGRES_USER" -d n8n_memory -c "\password cc_reader"

BEGIN;
CREATE SCHEMA claim_checks;

CREATE TABLE claim_checks.conversation_exchanges (
    conversation_id integer NOT NULL,
    exchange_no integer NOT NULL,
    asked_at timestamp with time zone DEFAULT now() NOT NULL,
    question text NOT NULL,
    answer text
);

CREATE TABLE claim_checks.conversation_messages (
    chat_id text NOT NULL,
    telegram_message_id bigint NOT NULL,
    conversation_id integer NOT NULL,
    exchange_no integer NOT NULL
);

CREATE TABLE claim_checks.stories (
    story_number integer NOT NULL,
    run_id text NOT NULL,
    cluster_id text,
    found_on date NOT NULL,
    mode text NOT NULL,
    keywords text,
    title text NOT NULL,
    label text NOT NULL,
    claim text,
    gist text,
    explainer jsonb,
    official_links text,
    supporting_links text,
    contradicting_links text,
    evidence text,
    pdf_link text,
    search_terms text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    search tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((((((((COALESCE(title, ''::text) || ' '::text) || COALESCE(claim, ''::text)) || ' '::text) || COALESCE(gist, ''::text)) || ' '::text) || COALESCE(keywords, ''::text)) || ' '::text) || COALESCE(search_terms, ''::text)) || ' '::text) || COALESCE((explainer)::text, ''::text)))) STORED,
    posts jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT stories_label_check CHECK ((label = ANY (ARRAY['Corroborated'::text, 'Single source'::text, 'Disputed'::text, 'Unverified'::text, 'Opinion'::text]))),
    CONSTRAINT stories_mode_check CHECK ((mode = ANY (ARRAY['today'::text, '7days'::text])))
);

ALTER TABLE claim_checks.stories ALTER COLUMN story_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME claim_checks.stories_story_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE claim_checks.story_conversations (
    conversation_id integer NOT NULL,
    chat_id text NOT NULL,
    story_number integer,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    last_message_at timestamp with time zone DEFAULT now() NOT NULL,
    active boolean DEFAULT true NOT NULL,
    summary text,
    saved_part text,
    saved_at timestamp with time zone,
    forgotten_at timestamp with time zone
);

ALTER TABLE claim_checks.story_conversations ALTER COLUMN conversation_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME claim_checks.story_conversations_conversation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE claim_checks.story_updates (
    update_id integer NOT NULL,
    story_number integer NOT NULL,
    asked_on timestamp with time zone DEFAULT now() NOT NULL,
    question text,
    result text NOT NULL,
    found_new boolean NOT NULL,
    links text
);

ALTER TABLE claim_checks.story_updates ALTER COLUMN update_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME claim_checks.story_updates_update_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY claim_checks.conversation_exchanges
    ADD CONSTRAINT conversation_exchanges_pkey PRIMARY KEY (conversation_id, exchange_no);

ALTER TABLE ONLY claim_checks.conversation_messages
    ADD CONSTRAINT conversation_messages_pkey PRIMARY KEY (chat_id, telegram_message_id);

ALTER TABLE ONLY claim_checks.stories
    ADD CONSTRAINT stories_pkey PRIMARY KEY (story_number);

ALTER TABLE ONLY claim_checks.story_conversations
    ADD CONSTRAINT story_conversations_pkey PRIMARY KEY (conversation_id);

ALTER TABLE ONLY claim_checks.story_updates
    ADD CONSTRAINT story_updates_pkey PRIMARY KEY (update_id);

CREATE INDEX stories_found_on_idx ON claim_checks.stories USING btree (found_on);

CREATE UNIQUE INDEX stories_run_cluster_idx ON claim_checks.stories USING btree (run_id, cluster_id);

CREATE INDEX stories_search_idx ON claim_checks.stories USING gin (search);

CREATE INDEX story_conversations_chat_idx ON claim_checks.story_conversations USING btree (chat_id, active, last_message_at DESC);

CREATE INDEX story_conversations_story_idx ON claim_checks.story_conversations USING btree (story_number) WHERE (summary IS NOT NULL);

CREATE INDEX story_updates_story_idx ON claim_checks.story_updates USING btree (story_number, asked_on);

ALTER TABLE ONLY claim_checks.conversation_exchanges
    ADD CONSTRAINT conversation_exchanges_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES claim_checks.story_conversations(conversation_id) ON DELETE CASCADE;

ALTER TABLE ONLY claim_checks.conversation_messages
    ADD CONSTRAINT conversation_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES claim_checks.story_conversations(conversation_id) ON DELETE CASCADE;

ALTER TABLE ONLY claim_checks.story_conversations
    ADD CONSTRAINT story_conversations_story_number_fkey FOREIGN KEY (story_number) REFERENCES claim_checks.stories(story_number);

ALTER TABLE ONLY claim_checks.story_updates
    ADD CONSTRAINT story_updates_story_number_fkey FOREIGN KEY (story_number) REFERENCES claim_checks.stories(story_number);

-- cc_reader: the read-only login the chat agent uses to search the archive with SQL (credential "Postgres Claim Checks Reader").
-- It can only read the claim_checks tables, and every query it sends runs read-only.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cc_reader') THEN CREATE ROLE cc_reader LOGIN; END IF; END $$;
ALTER ROLE cc_reader SET default_transaction_read_only = on;
ALTER ROLE cc_reader SET search_path = claim_checks;
DO $$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO cc_reader', current_database()); END $$;
GRANT USAGE ON SCHEMA claim_checks TO cc_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA claim_checks TO cc_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA claim_checks GRANT SELECT ON TABLES TO cc_reader;

COMMIT;
