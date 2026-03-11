-- ============================================================================
-- Comprehensive Sample Database for PostgresWire & PostgresKit Tests
-- ============================================================================
-- This fixture creates a realistic database with ALL PostgreSQL data types,
-- triggers, functions, views, permissions, and sample data to exercise
-- every feature of the postgres-wire library.
-- ============================================================================

-- ============================================================================
-- 0. EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "hstore";
CREATE EXTENSION IF NOT EXISTS "ltree";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ============================================================================
-- 1. CUSTOM TYPES (Enums, Composites, Domains)
-- ============================================================================

-- Enum types
DO $$ BEGIN
    CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral', 'excited', 'angry');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE priority_level AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Composite type
DO $$ BEGIN
    CREATE TYPE address_type AS (
        street TEXT,
        city TEXT,
        state TEXT,
        zip_code TEXT,
        country TEXT
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Domain types
DO $$ BEGIN
    CREATE DOMAIN positive_integer AS INTEGER CHECK (VALUE > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE DOMAIN email_address AS CITEXT CHECK (VALUE ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE DOMAIN percentage AS NUMERIC(5,2) CHECK (VALUE >= 0 AND VALUE <= 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 2. SCHEMAS
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS archive;

-- ============================================================================
-- 3. TABLES — Organized by data type coverage
-- ============================================================================

-- Drop all tables in dependency order
DROP TABLE IF EXISTS audit.change_log CASCADE;
DROP TABLE IF EXISTS app.order_items CASCADE;
DROP TABLE IF EXISTS app.orders CASCADE;
DROP TABLE IF EXISTS app.comments CASCADE;
DROP TABLE IF EXISTS app.posts CASCADE;
DROP TABLE IF EXISTS app.tags CASCADE;
DROP TABLE IF EXISTS app.post_tags CASCADE;
DROP TABLE IF EXISTS app.user_profiles CASCADE;
DROP TABLE IF EXISTS app.users CASCADE;
DROP TABLE IF EXISTS public.all_data_types CASCADE;
DROP TABLE IF EXISTS public.numeric_types CASCADE;
DROP TABLE IF EXISTS public.text_types CASCADE;
DROP TABLE IF EXISTS public.temporal_types CASCADE;
DROP TABLE IF EXISTS public.json_types CASCADE;
DROP TABLE IF EXISTS public.array_types CASCADE;
DROP TABLE IF EXISTS public.network_types CASCADE;
DROP TABLE IF EXISTS public.geometric_types CASCADE;
DROP TABLE IF EXISTS public.binary_types CASCADE;
DROP TABLE IF EXISTS public.range_types CASCADE;
DROP TABLE IF EXISTS public.special_types CASCADE;
DROP TABLE IF EXISTS public.fulltext_types CASCADE;
DROP TABLE IF EXISTS archive.archived_users CASCADE;

-- ---------------------------------------------------------------------------
-- 3a. Numeric Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.numeric_types (
    id                  SERIAL PRIMARY KEY,
    col_smallint        SMALLINT,
    col_integer         INTEGER,
    col_bigint          BIGINT,
    col_decimal         DECIMAL(12, 4),
    col_numeric         NUMERIC(20, 8),
    col_real            REAL,
    col_double          DOUBLE PRECISION,
    col_smallserial     SMALLSERIAL,
    col_serial          SERIAL,
    col_bigserial       BIGSERIAL,
    col_money           MONEY,
    col_positive        positive_integer
);

-- ---------------------------------------------------------------------------
-- 3b. Text / Character Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.text_types (
    id                  SERIAL PRIMARY KEY,
    col_char            CHAR(10),
    col_varchar         VARCHAR(255),
    col_varchar_unbound VARCHAR,
    col_text            TEXT,
    col_citext          CITEXT,
    col_name            NAME,
    col_xml             XML
);

-- ---------------------------------------------------------------------------
-- 3c. Temporal / Date-Time Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.temporal_types (
    id                  SERIAL PRIMARY KEY,
    col_date            DATE,
    col_time            TIME,
    col_time_tz         TIME WITH TIME ZONE,
    col_timestamp       TIMESTAMP,
    col_timestamp_tz    TIMESTAMP WITH TIME ZONE,
    col_interval        INTERVAL
);

-- ---------------------------------------------------------------------------
-- 3d. JSON / JSONB Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.json_types (
    id                  SERIAL PRIMARY KEY,
    col_json            JSON,
    col_jsonb           JSONB,
    col_jsonb_arr       JSONB DEFAULT '[]'::jsonb,
    col_jsonb_obj       JSONB DEFAULT '{}'::jsonb,
    col_hstore          HSTORE
);

-- Create GIN indexes for JSONB queries
CREATE INDEX IF NOT EXISTS idx_json_types_jsonb ON public.json_types USING GIN (col_jsonb);
CREATE INDEX IF NOT EXISTS idx_json_types_jsonb_path ON public.json_types USING GIN (col_jsonb jsonb_path_ops);

-- ---------------------------------------------------------------------------
-- 3e. Array Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.array_types (
    id                  SERIAL PRIMARY KEY,
    col_int_arr         INTEGER[],
    col_text_arr        TEXT[],
    col_bool_arr        BOOLEAN[],
    col_float_arr       REAL[],
    col_uuid_arr        UUID[],
    col_timestamp_arr   TIMESTAMP WITH TIME ZONE[],
    col_jsonb_arr       JSONB[],
    col_int_2d          INTEGER[][],
    col_varchar_arr     VARCHAR(100)[]
);

-- ---------------------------------------------------------------------------
-- 3f. Network Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.network_types (
    id                  SERIAL PRIMARY KEY,
    col_inet            INET,
    col_cidr            CIDR,
    col_macaddr         MACADDR,
    col_macaddr8        MACADDR8
);

-- ---------------------------------------------------------------------------
-- 3g. Geometric Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.geometric_types (
    id                  SERIAL PRIMARY KEY,
    col_point           POINT,
    col_line            LINE,
    col_lseg            LSEG,
    col_box             BOX,
    col_path_open       PATH,
    col_path_closed     PATH,
    col_polygon         POLYGON,
    col_circle          CIRCLE
);

-- ---------------------------------------------------------------------------
-- 3h. Binary Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.binary_types (
    id                  SERIAL PRIMARY KEY,
    col_bytea           BYTEA,
    col_bit             BIT(8),
    col_bit_varying     BIT VARYING(64)
);

-- ---------------------------------------------------------------------------
-- 3i. Range Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.range_types (
    id                  SERIAL PRIMARY KEY,
    col_int4range       INT4RANGE,
    col_int8range       INT8RANGE,
    col_numrange        NUMRANGE,
    col_tsrange         TSRANGE,
    col_tstzrange       TSTZRANGE,
    col_daterange       DATERANGE
);

-- ---------------------------------------------------------------------------
-- 3j. Full-Text Search Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.fulltext_types (
    id                  SERIAL PRIMARY KEY,
    col_tsvector        TSVECTOR,
    col_tsquery         TSQUERY,
    col_text            TEXT
);

-- Create GIN index for full-text search
CREATE INDEX IF NOT EXISTS idx_fulltext_tsvector ON public.fulltext_types USING GIN (col_tsvector);

-- ---------------------------------------------------------------------------
-- 3k. Special / Miscellaneous Types
-- ---------------------------------------------------------------------------
CREATE TABLE public.special_types (
    id                  SERIAL PRIMARY KEY,
    col_uuid            UUID DEFAULT uuid_generate_v4(),
    col_boolean         BOOLEAN,
    col_ltree           LTREE,
    col_mood            mood,
    col_priority        priority_level,
    col_oid             OID,
    col_regclass        REGCLASS,
    col_pg_lsn          PG_LSN
);

-- ---------------------------------------------------------------------------
-- 3l. Comprehensive "all types in one" reference table
-- ---------------------------------------------------------------------------
CREATE TABLE public.all_data_types (
    id                  BIGSERIAL PRIMARY KEY,
    -- Numeric
    col_smallint        SMALLINT NOT NULL DEFAULT 0,
    col_integer         INTEGER,
    col_bigint          BIGINT,
    col_decimal         DECIMAL(18, 6),
    col_numeric         NUMERIC,
    col_real            REAL,
    col_double          DOUBLE PRECISION,
    col_money           MONEY,
    -- Character
    col_char            CHAR(5),
    col_varchar         VARCHAR(200),
    col_text            TEXT,
    -- Boolean
    col_boolean         BOOLEAN DEFAULT false,
    -- Date/Time
    col_date            DATE,
    col_time            TIME,
    col_time_tz         TIME WITH TIME ZONE,
    col_timestamp       TIMESTAMP,
    col_timestamp_tz    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    col_interval        INTERVAL,
    -- UUID
    col_uuid            UUID DEFAULT uuid_generate_v4(),
    -- JSON
    col_json            JSON,
    col_jsonb           JSONB,
    -- Binary
    col_bytea           BYTEA,
    -- Network
    col_inet            INET,
    col_cidr            CIDR,
    col_macaddr         MACADDR,
    -- Geometric
    col_point           POINT,
    col_box             BOX,
    -- Arrays
    col_int_arr         INTEGER[],
    col_text_arr        TEXT[],
    -- Range
    col_int4range       INT4RANGE,
    col_tstzrange       TSTZRANGE,
    -- Full-text
    col_tsvector        TSVECTOR,
    -- Enum
    col_mood            mood,
    -- XML
    col_xml             XML,
    -- Bit
    col_bit             BIT(8),
    col_bit_varying     BIT VARYING(32),
    -- Special
    col_hstore          HSTORE
);

-- ============================================================================
-- 4. APPLICATION TABLES (realistic relational model)
-- ============================================================================

CREATE TABLE app.users (
    id                  BIGSERIAL PRIMARY KEY,
    username            CITEXT NOT NULL UNIQUE,
    email               email_address NOT NULL,
    password_hash       TEXT NOT NULL DEFAULT 'hashed_placeholder',
    display_name        VARCHAR(100),
    bio                 TEXT,
    avatar_url          TEXT,
    metadata            JSONB DEFAULT '{}'::jsonb,
    settings            JSONB DEFAULT '{"theme": "light", "notifications": true}'::jsonb,
    tags                TEXT[] DEFAULT '{}',
    mood                mood DEFAULT 'neutral',
    is_active           BOOLEAN DEFAULT true,
    is_verified         BOOLEAN DEFAULT false,
    login_count         INTEGER DEFAULT 0,
    last_login_at       TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_username_length CHECK (length(username::text) >= 3)
);

CREATE TABLE app.user_profiles (
    user_id             BIGINT PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
    first_name          VARCHAR(50),
    last_name           VARCHAR(50),
    date_of_birth       DATE,
    phone               VARCHAR(20),
    address             address_type,
    social_links        JSONB DEFAULT '{}'::jsonb,
    interests           TEXT[],
    profile_score       percentage DEFAULT 0.00,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE app.posts (
    id                  BIGSERIAL PRIMARY KEY,
    author_id           BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    title               VARCHAR(300) NOT NULL,
    slug                CITEXT NOT NULL UNIQUE,
    content             TEXT,
    excerpt             VARCHAR(500),
    metadata            JSONB DEFAULT '{}'::jsonb,
    search_vector       TSVECTOR,
    status              order_status DEFAULT 'pending',
    priority            priority_level DEFAULT 'medium',
    view_count          INTEGER DEFAULT 0,
    rating              NUMERIC(3, 2),
    is_featured         BOOLEAN DEFAULT false,
    published_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT posts_rating_range CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5))
);

-- Full-text search index on posts
CREATE INDEX IF NOT EXISTS idx_posts_search ON app.posts USING GIN (search_vector);
CREATE INDEX IF NOT EXISTS idx_posts_metadata ON app.posts USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_posts_author ON app.posts (author_id);
CREATE INDEX IF NOT EXISTS idx_posts_status ON app.posts (status);
CREATE INDEX IF NOT EXISTS idx_posts_published ON app.posts (published_at DESC NULLS LAST);

CREATE TABLE app.tags (
    id                  SERIAL PRIMARY KEY,
    name                CITEXT NOT NULL UNIQUE,
    slug                CITEXT NOT NULL UNIQUE,
    description         TEXT,
    color               CHAR(7) DEFAULT '#000000',
    post_count          INTEGER DEFAULT 0,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE app.post_tags (
    post_id             BIGINT NOT NULL REFERENCES app.posts(id) ON DELETE CASCADE,
    tag_id              INTEGER NOT NULL REFERENCES app.tags(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);

CREATE TABLE app.comments (
    id                  BIGSERIAL PRIMARY KEY,
    post_id             BIGINT NOT NULL REFERENCES app.posts(id) ON DELETE CASCADE,
    author_id           BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    parent_id           BIGINT REFERENCES app.comments(id) ON DELETE SET NULL,
    content             TEXT NOT NULL,
    metadata            JSONB DEFAULT '{}'::jsonb,
    is_edited           BOOLEAN DEFAULT false,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_comments_post ON app.comments (post_id);
CREATE INDEX IF NOT EXISTS idx_comments_author ON app.comments (author_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON app.comments (parent_id);

CREATE TABLE app.orders (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             BIGINT NOT NULL REFERENCES app.users(id),
    status              order_status DEFAULT 'pending',
    total_amount        MONEY,
    shipping_address    address_type,
    notes               TEXT,
    metadata            JSONB DEFAULT '{}'::jsonb,
    valid_during        TSTZRANGE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE app.order_items (
    id                  BIGSERIAL PRIMARY KEY,
    order_id            BIGINT NOT NULL REFERENCES app.orders(id) ON DELETE CASCADE,
    product_name        VARCHAR(200) NOT NULL,
    quantity            positive_integer NOT NULL,
    unit_price          MONEY NOT NULL,
    discount_pct        percentage DEFAULT 0,
    metadata            JSONB DEFAULT '{}'::jsonb
);

-- ============================================================================
-- 5. AUDIT TABLE
-- ============================================================================
CREATE TABLE audit.change_log (
    id                  BIGSERIAL PRIMARY KEY,
    table_schema        TEXT NOT NULL,
    table_name          TEXT NOT NULL,
    operation           TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
    row_id              BIGINT,
    old_data            JSONB,
    new_data            JSONB,
    changed_by          TEXT DEFAULT current_user,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 6. ARCHIVE TABLE (for partition-like testing)
-- ============================================================================
CREATE TABLE archive.archived_users (
    LIKE app.users INCLUDING ALL,
    archived_at         TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    archived_reason     TEXT
);

-- ============================================================================
-- 7. VIEWS
-- ============================================================================
CREATE OR REPLACE VIEW app.active_users AS
    SELECT id, username, email, display_name, last_login_at, created_at
    FROM app.users
    WHERE is_active = true;

CREATE OR REPLACE VIEW app.published_posts AS
    SELECT p.id, p.title, p.slug, p.excerpt, p.view_count, p.rating,
           p.published_at, u.username AS author_username
    FROM app.posts p
    JOIN app.users u ON u.id = p.author_id
    WHERE p.status = 'delivered' AND p.published_at IS NOT NULL;

CREATE OR REPLACE VIEW app.post_statistics AS
    SELECT p.id, p.title,
           COUNT(c.id) AS comment_count,
           COALESCE(AVG(p.rating), 0) AS avg_rating,
           p.view_count
    FROM app.posts p
    LEFT JOIN app.comments c ON c.post_id = p.id
    GROUP BY p.id, p.title, p.view_count;

-- ============================================================================
-- 8. MATERIALIZED VIEW
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS app.user_activity_summary AS
    SELECT u.id AS user_id,
           u.username,
           COUNT(DISTINCT p.id) AS post_count,
           COUNT(DISTINCT c.id) AS comment_count,
           MAX(p.created_at) AS last_post_at,
           MAX(c.created_at) AS last_comment_at
    FROM app.users u
    LEFT JOIN app.posts p ON p.author_id = u.id
    LEFT JOIN app.comments c ON c.author_id = u.id
    GROUP BY u.id, u.username;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_activity_user_id ON app.user_activity_summary (user_id);

-- ============================================================================
-- 9. SEQUENCES
-- ============================================================================
CREATE SEQUENCE IF NOT EXISTS app.invoice_number_seq
    START WITH 1000
    INCREMENT BY 1
    NO MAXVALUE
    CACHE 10;

CREATE SEQUENCE IF NOT EXISTS app.ticket_number_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 999999
    CYCLE;

-- ============================================================================
-- 10. FUNCTIONS
-- ============================================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION app.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function: Update post search vector
CREATE OR REPLACE FUNCTION app.update_post_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector = to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function: Audit logging
CREATE OR REPLACE FUNCTION audit.log_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit.change_log (table_schema, table_name, operation, row_id, old_data)
        VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, OLD.id, to_jsonb(OLD));
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.change_log (table_schema, table_name, operation, row_id, old_data, new_data)
        VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit.change_log (table_schema, table_name, operation, row_id, new_data)
        VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Increment tag post count
CREATE OR REPLACE FUNCTION app.update_tag_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE app.tags SET post_count = post_count + 1 WHERE id = NEW.tag_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE app.tags SET post_count = post_count - 1 WHERE id = OLD.tag_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Increment user login count
CREATE OR REPLACE FUNCTION app.increment_login_count(p_user_id BIGINT)
RETURNS void AS $$
BEGIN
    UPDATE app.users
    SET login_count = login_count + 1,
        last_login_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Pure SQL function returning a table
CREATE OR REPLACE FUNCTION app.get_user_posts(p_user_id BIGINT)
RETURNS TABLE(post_id BIGINT, title VARCHAR, status order_status, created_at TIMESTAMPTZ) AS $$
    SELECT id, title, status, created_at
    FROM app.posts
    WHERE author_id = p_user_id
    ORDER BY created_at DESC;
$$ LANGUAGE sql STABLE;

-- Function: JSONB manipulation helper
CREATE OR REPLACE FUNCTION app.merge_jsonb_settings(
    current_settings JSONB,
    new_settings JSONB
) RETURNS JSONB AS $$
    SELECT current_settings || new_settings;
$$ LANGUAGE sql IMMUTABLE;

-- ============================================================================
-- 11. TRIGGERS
-- ============================================================================

-- Updated_at triggers
CREATE OR REPLACE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON app.users
    FOR EACH ROW EXECUTE FUNCTION app.update_updated_at();

CREATE OR REPLACE TRIGGER trg_posts_updated_at
    BEFORE UPDATE ON app.posts
    FOR EACH ROW EXECUTE FUNCTION app.update_updated_at();

CREATE OR REPLACE TRIGGER trg_comments_updated_at
    BEFORE UPDATE ON app.comments
    FOR EACH ROW EXECUTE FUNCTION app.update_updated_at();

CREATE OR REPLACE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON app.orders
    FOR EACH ROW EXECUTE FUNCTION app.update_updated_at();

-- Search vector trigger
CREATE OR REPLACE TRIGGER trg_posts_search_vector
    BEFORE INSERT OR UPDATE OF title, content ON app.posts
    FOR EACH ROW EXECUTE FUNCTION app.update_post_search_vector();

-- Tag count trigger
CREATE OR REPLACE TRIGGER trg_post_tags_count
    AFTER INSERT OR DELETE ON app.post_tags
    FOR EACH ROW EXECUTE FUNCTION app.update_tag_count();

-- Audit triggers on users and posts
CREATE OR REPLACE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON app.users
    FOR EACH ROW EXECUTE FUNCTION audit.log_change();

CREATE OR REPLACE TRIGGER trg_posts_audit
    AFTER INSERT OR UPDATE OR DELETE ON app.posts
    FOR EACH ROW EXECUTE FUNCTION audit.log_change();

-- ============================================================================
-- 12. SAMPLE DATA — Numeric types
-- ============================================================================
INSERT INTO public.numeric_types (col_smallint, col_integer, col_bigint, col_decimal, col_numeric, col_real, col_double, col_money, col_positive)
VALUES
    (32767, 2147483647, 9223372036854775807, 99999999.9999, 123456789012.56789012, 3.14159, 3.141592653589793, 1234.56, 42),
    (-32768, -2147483648, -9223372036854775808, -99999999.9999, -123456789012.56789012, -3.14159, -3.141592653589793, -1234.56, 1),
    (0, 0, 0, 0.0000, 0.00000000, 0.0, 0.0, 0.00, 1),
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 13. SAMPLE DATA — Text types
-- ============================================================================
INSERT INTO public.text_types (col_char, col_varchar, col_varchar_unbound, col_text, col_citext, col_name, col_xml)
VALUES
    ('ABCDEFGHIJ', 'Hello, World!', 'Unbounded varchar value', 'This is a longer text value for testing purposes.', 'CaseInsensitive', 'identifier_name', '<root><element attr="value">text content</element></root>'),
    ('          ', '', '', '', '', '', '<empty/>'),
    ('Unicode™  ', 'Héllo Wörld! 日本語 中文 한국어 العربية', 'Emoji test: 🎉🚀💯🔥', E'Line1\nLine2\tTabbed\r\nWindows', 'UPPERCASE', 'a_b_c_123', '<data><item id="1">café</item></data>'),
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 14. SAMPLE DATA — Temporal types
-- ============================================================================
INSERT INTO public.temporal_types (col_date, col_time, col_time_tz, col_timestamp, col_timestamp_tz, col_interval)
VALUES
    ('2024-01-15', '14:30:00', '14:30:00+05:30', '2024-01-15 14:30:00', '2024-01-15 14:30:00+00', '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'),
    ('1970-01-01', '00:00:00', '00:00:00+00', '1970-01-01 00:00:00', '1970-01-01 00:00:00+00', '0 seconds'),
    ('9999-12-31', '23:59:59.999999', '23:59:59.999999+12', '9999-12-31 23:59:59.999999', '9999-12-31 23:59:59.999999+00', '-1 year -2 months'),
    ('2000-02-29', '12:00:00', '12:00:00-08', '2000-02-29 12:00:00', '2000-02-29 12:00:00-08', '30 days'),
    (NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 15. SAMPLE DATA — JSON / JSONB types
-- ============================================================================
INSERT INTO public.json_types (col_json, col_jsonb, col_jsonb_arr, col_jsonb_obj, col_hstore)
VALUES
    -- Simple flat object
    ('{"name": "Alice", "age": 30}',
     '{"name": "Alice", "age": 30, "active": true}',
     '[1, 2, 3]',
     '{"key": "value"}',
     '"name"=>"Alice", "age"=>"30"'),
    -- Deeply nested object
    ('{"level1": {"level2": {"level3": {"level4": "deep"}}}}',
     '{"users": [{"id": 1, "name": "Alice", "roles": ["admin", "user"]}, {"id": 2, "name": "Bob", "roles": ["user"]}]}',
     '["string", 42, true, null, {"nested": "object"}]',
     '{"config": {"database": {"host": "localhost", "port": 5432}, "cache": {"ttl": 3600}}}',
     '"host"=>"localhost", "port"=>"5432", "ssl"=>"true"'),
    -- Numeric precision in JSON
    ('{"integer": 42, "float": 3.14, "scientific": 1.23e10, "negative": -99}',
     '{"price": 19.99, "quantity": 100, "discount": 0.15, "total": 1699.15}',
     '[]',
     '{}',
     ''),
    -- Special characters and Unicode
    ('{"emoji": "🎉", "unicode": "日本語", "html": "<script>alert(1)</script>"}',
     '{"path": "/usr/local/bin", "regex": "^[a-z]+$", "sql": "SELECT * FROM t WHERE x = ''y''", "newline": "line1\nline2"}',
     '["café", "naïve", "résumé"]',
     '{"escape": "quotes\"inside", "backslash": "path\\to\\file"}',
     '"key with spaces"=>"value with spaces", "special=chars"=>"value=>more"'),
    -- Null and empty
    (NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 16. SAMPLE DATA — Array types
-- ============================================================================
INSERT INTO public.array_types (col_int_arr, col_text_arr, col_bool_arr, col_float_arr, col_uuid_arr, col_timestamp_arr, col_jsonb_arr, col_int_2d, col_varchar_arr)
VALUES
    ('{1,2,3,4,5}', '{"hello","world","foo"}', '{true,false,true}', '{1.1,2.2,3.3}',
     ARRAY[uuid_generate_v4(), uuid_generate_v4()]::UUID[],
     ARRAY[NOW(), NOW() - INTERVAL '1 day']::TIMESTAMPTZ[],
     ARRAY['{"a":1}'::jsonb, '{"b":2}'::jsonb],
     '{{1,2,3},{4,5,6}}',
     '{"short","medium length","a longer varchar value"}'),
    -- Empty arrays
    ('{}', '{}', '{}', '{}', '{}', '{}', '{}', '{}', '{}'),
    -- Single element
    ('{42}', '{"only"}', '{true}', '{0.0}', ARRAY[uuid_generate_v4()]::UUID[], ARRAY[NOW()]::TIMESTAMPTZ[], ARRAY['null'::jsonb], '{{1}}', '{"one"}'),
    -- NULL
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 17. SAMPLE DATA — Network types
-- ============================================================================
INSERT INTO public.network_types (col_inet, col_cidr, col_macaddr, col_macaddr8)
VALUES
    ('192.168.1.1', '192.168.1.0/24', '08:00:2b:01:02:03', '08:00:2b:01:02:03:04:05'),
    ('::1', '::1/128', 'ff:ff:ff:ff:ff:ff', 'ff:ff:ff:ff:ff:ff:ff:ff'),
    ('10.0.0.1/8', '10.0.0.0/8', '00:00:00:00:00:00', '00:00:00:00:00:00:00:00'),
    ('2001:db8::1', '2001:db8::/32', 'a1:b2:c3:d4:e5:f6', 'a1:b2:c3:d4:e5:f6:a7:b8'),
    (NULL, NULL, NULL, NULL);

-- ============================================================================
-- 18. SAMPLE DATA — Geometric types
-- ============================================================================
INSERT INTO public.geometric_types (col_point, col_line, col_lseg, col_box, col_path_open, col_path_closed, col_polygon, col_circle)
VALUES
    ('(1.0, 2.0)', '{1, -1, 0}', '((0,0),(1,1))', '((1,1),(0,0))', '[(0,0),(1,1),(2,0)]', '((0,0),(1,1),(2,0))', '((0,0),(1,0),(1,1),(0,1))', '<(0,0),5>'),
    ('(0, 0)', '{0, 1, 0}', '((-1,-1),(1,1))', '((10,10),(-10,-10))', '[(0,0),(5,5)]', '((0,0),(3,4),(6,0))', '((0,0),(2,0),(2,2),(0,2))', '<(3,4),10>'),
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 19. SAMPLE DATA — Binary types
-- ============================================================================
INSERT INTO public.binary_types (col_bytea, col_bit, col_bit_varying)
VALUES
    (E'\\x48656C6C6F', B'10101010', B'1100110011001100'),
    (E'\\x00FF00FF', B'00000000', B'1'),
    (E'\\x', B'11111111', B'0'),
    (NULL, NULL, NULL);

-- ============================================================================
-- 20. SAMPLE DATA — Range types
-- ============================================================================
INSERT INTO public.range_types (col_int4range, col_int8range, col_numrange, col_tsrange, col_tstzrange, col_daterange)
VALUES
    ('[1, 10)', '[1, 1000000)', '[0.0, 100.0]', '[2024-01-01, 2024-12-31)', '[2024-01-01 00:00:00+00, 2024-12-31 23:59:59+00]', '[2024-01-01, 2024-12-31)'),
    ('(5, 15]', '(0, 100]', '(0.0, 1.0)', '[2024-06-01, 2024-06-30]', '[2024-06-01 00:00:00+00, 2024-06-30 23:59:59+00]', '[2024-06-01, 2024-06-30]'),
    ('empty', 'empty', 'empty', 'empty', 'empty', 'empty'),
    (NULL, NULL, NULL, NULL, NULL, NULL);

-- ============================================================================
-- 21. SAMPLE DATA — Full-text search types
-- ============================================================================
INSERT INTO public.fulltext_types (col_tsvector, col_tsquery, col_text)
VALUES
    (to_tsvector('english', 'The quick brown fox jumps over the lazy dog'), to_tsquery('english', 'quick & fox'), 'The quick brown fox jumps over the lazy dog'),
    (to_tsvector('english', 'PostgreSQL is an advanced open source relational database'), to_tsquery('english', 'postgres | database'), 'PostgreSQL is an advanced open source relational database'),
    (to_tsvector('english', 'Swift programming language for iOS and macOS development'), to_tsquery('english', 'swift & !objective'), 'Swift programming language for iOS and macOS development'),
    (NULL, NULL, NULL);

-- ============================================================================
-- 22. SAMPLE DATA — Special types
-- ============================================================================
INSERT INTO public.special_types (col_boolean, col_ltree, col_mood, col_priority)
VALUES
    (true, 'root.science.astronomy', 'happy', 'high'),
    (false, 'root.science.biology.genetics', 'sad', 'low'),
    (true, 'root.technology.programming.swift', 'excited', 'critical'),
    (NULL, 'root', 'neutral', 'medium'),
    (NULL, NULL, NULL, NULL);

-- ============================================================================
-- 23. SAMPLE DATA — All types in one row
-- ============================================================================
INSERT INTO public.all_data_types (
    col_smallint, col_integer, col_bigint, col_decimal, col_numeric, col_real, col_double, col_money,
    col_char, col_varchar, col_text, col_boolean,
    col_date, col_time, col_time_tz, col_timestamp, col_timestamp_tz, col_interval,
    col_uuid, col_json, col_jsonb, col_bytea,
    col_inet, col_cidr, col_macaddr,
    col_point, col_box,
    col_int_arr, col_text_arr,
    col_int4range, col_tstzrange,
    col_tsvector, col_mood, col_xml, col_bit, col_bit_varying, col_hstore
) VALUES (
    100, 200000, 9000000000, 12345.678900, 99.99, 2.71828, 2.718281828459045, 42.00,
    'ABCDE', 'Test varchar', 'Full text content with Unicode: 日本語', true,
    '2024-06-15', '10:30:00', '10:30:00-07', '2024-06-15 10:30:00', '2024-06-15 10:30:00-07', '1 year 6 months',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '{"test": true}', '{"key": "value", "nested": {"a": 1}}', E'\\xDEADBEEF',
    '10.0.0.1', '10.0.0.0/24', '08:00:2b:01:02:03',
    '(1.5, 2.5)', '((3,4),(1,2))',
    '{1,2,3}', '{"a","b","c"}',
    '[1, 100)', '[2024-01-01 00:00:00+00, 2025-01-01 00:00:00+00)',
    to_tsvector('english', 'comprehensive data type test'), 'happy',
    '<test>data</test>', B'11001100', B'101010101010', '"key1"=>"val1", "key2"=>"val2"'
);

-- Also insert an all-NULL row for null handling tests
INSERT INTO public.all_data_types (col_smallint) VALUES (1);

-- ============================================================================
-- 24. APPLICATION SAMPLE DATA
-- ============================================================================

-- Users
INSERT INTO app.users (username, email, display_name, bio, metadata, settings, tags, mood, is_verified)
VALUES
    ('alice', 'alice@example.com', 'Alice Johnson', 'Software engineer and PostgreSQL enthusiast',
     '{"github": "alice", "twitter": "@alice_dev", "experience_years": 8}',
     '{"theme": "dark", "notifications": true, "language": "en"}',
     '{"postgresql", "swift", "rust"}', 'happy', true),
    ('bob', 'bob@example.com', 'Bob Smith', 'Database administrator',
     '{"github": "bobdb", "certifications": ["AWS", "PG"]}',
     '{"theme": "light", "notifications": false, "language": "en"}',
     '{"dba", "linux", "docker"}', 'neutral', true),
    ('charlie', 'charlie@example.com', 'Charlie Brown', NULL,
     '{}',
     '{"theme": "light", "notifications": true, "language": "fr"}',
     '{}', 'neutral', false),
    ('diana', 'diana@example.com', 'Diana Prince', 'Full-stack developer',
     '{"specialties": ["frontend", "backend", "devops"]}',
     '{"theme": "auto", "notifications": true, "language": "es"}',
     '{"javascript", "python", "go"}', 'excited', true),
    ('eve', 'eve@example.com', 'Eve Wilson', 'Security researcher',
     '{"pgp_key": "0xDEADBEEF", "publications": 12}',
     '{"theme": "dark", "notifications": false, "language": "en"}',
     '{"security", "cryptography"}', 'neutral', true);

-- User profiles
INSERT INTO app.user_profiles (user_id, first_name, last_name, date_of_birth, phone, address, social_links, interests, profile_score)
VALUES
    (1, 'Alice', 'Johnson', '1992-03-15', '+1-555-0101',
     ROW('123 Main St', 'San Francisco', 'CA', '94105', 'US')::address_type,
     '{"linkedin": "alice-johnson", "website": "https://alice.dev"}',
     '{"databases", "distributed systems", "functional programming"}', 85.50),
    (2, 'Bob', 'Smith', '1988-07-22', '+1-555-0102',
     ROW('456 Oak Ave', 'Portland', 'OR', '97201', 'US')::address_type,
     '{"linkedin": "bob-smith-dba"}',
     '{"postgres", "monitoring", "performance tuning"}', 92.00),
    (4, 'Diana', 'Prince', '1995-11-30', '+44-20-7946-0958',
     ROW('10 Downing St', 'London', '', 'SW1A 2AA', 'UK')::address_type,
     '{"github": "diana-dev", "blog": "https://diana.codes"}',
     '{"web development", "cloud computing", "open source"}', 78.25);

-- Tags
INSERT INTO app.tags (name, slug, description, color)
VALUES
    ('PostgreSQL', 'postgresql', 'PostgreSQL database topics', '#336791'),
    ('Swift', 'swift', 'Swift programming language', '#FA7343'),
    ('Tutorial', 'tutorial', 'Tutorial and how-to content', '#28A745'),
    ('Performance', 'performance', 'Performance optimization', '#DC3545'),
    ('Security', 'security', 'Security best practices', '#FFC107');

-- Posts
INSERT INTO app.posts (author_id, title, slug, content, excerpt, metadata, status, priority, view_count, rating, is_featured, published_at)
VALUES
    (1, 'Getting Started with PostgreSQL and Swift', 'getting-started-postgresql-swift',
     'PostgreSQL is a powerful, open source object-relational database system. In this tutorial, we will explore how to use PostgreSQL with Swift using the postgres-wire library.',
     'Learn how to connect Swift applications to PostgreSQL',
     '{"read_time_minutes": 8, "difficulty": "beginner", "tags": ["postgresql", "swift"]}',
     'delivered', 'high', 1250, 4.50, true, NOW() - INTERVAL '30 days'),
    (1, 'Advanced JSONB Queries in PostgreSQL', 'advanced-jsonb-queries',
     'JSONB in PostgreSQL provides powerful JSON storage and querying capabilities. This guide covers operators like @>, ?, ?|, ?&, #>, and path queries.',
     'Master JSONB operators and indexing strategies',
     '{"read_time_minutes": 15, "difficulty": "advanced", "series": "PostgreSQL Deep Dive", "part": 1}',
     'delivered', 'critical', 3400, 4.85, true, NOW() - INTERVAL '15 days'),
    (2, 'Docker-based Integration Testing for Databases', 'docker-integration-testing',
     'Learn how to set up reliable integration tests using Docker containers for your database layer.',
     'Automate your database tests with Docker',
     '{"read_time_minutes": 10, "difficulty": "intermediate"}',
     'delivered', 'medium', 890, 4.20, false, NOW() - INTERVAL '7 days'),
    (4, 'Understanding PostgreSQL Range Types', 'understanding-range-types',
     'Range types are a unique feature of PostgreSQL that represent a range of values. They support int4range, int8range, numrange, tsrange, tstzrange, and daterange.',
     'A deep dive into PostgreSQL range types',
     '{"read_time_minutes": 12, "difficulty": "intermediate"}',
     'processing', 'medium', 0, NULL, false, NULL),
    (1, 'Draft: Full-Text Search with tsvector', 'fulltext-search-tsvector',
     'Exploring PostgreSQL full-text search capabilities...',
     NULL,
     '{"draft": true}',
     'pending', 'low', 0, NULL, false, NULL);

-- Post-tag associations
INSERT INTO app.post_tags (post_id, tag_id) VALUES
    (1, 1), (1, 2), (1, 3),
    (2, 1), (2, 4),
    (3, 3), (3, 4),
    (4, 1);

-- Comments (including nested/threaded)
INSERT INTO app.comments (post_id, author_id, parent_id, content, metadata)
VALUES
    (1, 2, NULL, 'Great introduction! Very helpful for getting started.', '{"helpful_votes": 5}'),
    (1, 4, NULL, 'Would love to see a follow-up on connection pooling.', '{"helpful_votes": 3}'),
    (1, 1, 1, 'Thanks Bob! Connection pooling article is in the works.', '{}'),
    (2, 5, NULL, 'The section on GIN indexes was particularly useful.', '{"helpful_votes": 12}'),
    (2, 2, 4, 'Agreed! GIN vs GiST comparison would be nice too.', '{"helpful_votes": 2}'),
    (3, 1, NULL, 'This is exactly what we use in postgres-wire!', '{}');

-- Orders
INSERT INTO app.orders (user_id, status, total_amount, shipping_address, notes, metadata, valid_during)
VALUES
    (1, 'delivered', 129.99,
     ROW('123 Main St', 'San Francisco', 'CA', '94105', 'US')::address_type,
     'Leave at door',
     '{"tracking": "1Z999AA10123456784", "carrier": "UPS"}',
     '[2024-01-01 00:00:00+00, 2024-12-31 23:59:59+00]'),
    (2, 'processing', 49.99,
     ROW('456 Oak Ave', 'Portland', 'OR', '97201', 'US')::address_type,
     NULL,
     '{"priority": true}',
     '[2024-06-01 00:00:00+00, 2024-06-30 23:59:59+00]'),
    (1, 'pending', 299.99,
     ROW('123 Main St', 'San Francisco', 'CA', '94105', 'US')::address_type,
     'Gift wrap please',
     '{}',
     NULL);

-- Order items
INSERT INTO app.order_items (order_id, product_name, quantity, unit_price, discount_pct, metadata)
VALUES
    (1, 'PostgreSQL Handbook', 3, 29.99, 10.00, '{"isbn": "978-0-123456-78-9"}'),
    (1, 'Swift Stickers Pack', 2, 9.99, 0.00, '{}'),
    (2, 'Database Poster', 1, 49.99, 0.00, '{"size": "24x36"}'),
    (3, 'Server Rack', 1, 299.99, 0.00, '{"weight_kg": 15.5}');

-- ============================================================================
-- 25. ROLES AND PERMISSIONS (for permission testing)
-- ============================================================================

-- Create test roles (idempotent)
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'test_readonly') THEN
        CREATE ROLE test_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'test_readwrite') THEN
        CREATE ROLE test_readwrite NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'test_app_user') THEN
        CREATE ROLE test_app_user LOGIN PASSWORD 'testpass123';
    END IF;
END $$;

-- Grant schema usage
GRANT USAGE ON SCHEMA app TO test_readonly;
GRANT USAGE ON SCHEMA app TO test_readwrite;
GRANT USAGE ON SCHEMA app TO test_app_user;

-- Read-only: SELECT on all app tables
GRANT SELECT ON ALL TABLES IN SCHEMA app TO test_readonly;

-- Read-write: SELECT, INSERT, UPDATE, DELETE on app tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO test_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO test_readwrite;

-- App user inherits readonly
GRANT test_readonly TO test_app_user;

-- ============================================================================
-- 26. REFRESH MATERIALIZED VIEW
-- ============================================================================
REFRESH MATERIALIZED VIEW app.user_activity_summary;

-- ============================================================================
-- 27. TABLE AND COLUMN COMMENTS
-- ============================================================================
COMMENT ON TABLE app.users IS 'Core user accounts table';
COMMENT ON TABLE app.posts IS 'Blog posts and articles';
COMMENT ON TABLE app.comments IS 'User comments on posts (supports threading)';
COMMENT ON TABLE public.all_data_types IS 'Reference table containing every supported PostgreSQL data type';
COMMENT ON COLUMN app.users.metadata IS 'Flexible JSONB field for user metadata (social links, preferences, etc.)';
COMMENT ON COLUMN app.users.settings IS 'User application settings stored as JSONB';
COMMENT ON COLUMN app.posts.search_vector IS 'Auto-generated tsvector for full-text search on title and content';

-- ============================================================================
-- Done! This database covers:
-- - ALL standard PostgreSQL data types (40+ types)
-- - Custom types: enums, composites, domains
-- - Extensions: uuid-ossp, hstore, ltree, citext
-- - 3 schemas: public, app, audit, archive
-- - 20+ tables with realistic relationships
-- - Foreign keys with CASCADE/SET NULL actions
-- - CHECK constraints, UNIQUE constraints
-- - Indexes: B-tree, GIN, GIN with jsonb_path_ops
-- - Full-text search: tsvector, tsquery, GIN index
-- - Views, materialized views
-- - Functions: PL/pgSQL and pure SQL
-- - Triggers: BEFORE UPDATE, BEFORE INSERT, AFTER INSERT/UPDATE/DELETE
-- - Sequences with options (START, INCREMENT, CYCLE)
-- - Roles and permissions (readonly, readwrite, app user)
-- - Audit logging via triggers
-- - JSONB: nested objects, arrays, operators, path queries
-- - Arrays: 1D, 2D, various element types
-- - Range types: int4, int8, numeric, timestamp, date
-- - Network types: inet, cidr, macaddr, macaddr8
-- - Geometric types: point, line, lseg, box, path, polygon, circle
-- - Binary: bytea, bit, bit varying
-- - Boundary values: min/max for each type, NULLs, empty strings
-- - Unicode/special characters in text data
-- - Threaded comments (self-referential FK)
-- - Composite type columns
-- - Money type
-- - XML type
-- ============================================================================
