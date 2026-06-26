-- MeetFlow — schema_v2.sql
-- Run this in your Supabase SQL Editor BEFORE using the app.
-- Safe to re-run; uses IF NOT EXISTS / ON CONFLICT DO NOTHING.

-- ─────────────────────────── SECTIONS ────────────────────────────
CREATE TABLE IF NOT EXISTS sections (
  id   serial PRIMARY KEY,
  name text   NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────── ROOMS ────────────────────────────────
CREATE TABLE IF NOT EXISTS rooms (
  id       serial  PRIMARY KEY,
  name     text    NOT NULL,
  capacity integer DEFAULT 0,
  end_hour integer DEFAULT 20,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────── STAFF ────────────────────────────────
CREATE TABLE IF NOT EXISTS staff (
  id                   serial  PRIMARY KEY,
  svc_no               text    NOT NULL UNIQUE,
  name                 text    NOT NULL,
  email                text,
  section_id           integer REFERENCES sections(id),
  password             text    NOT NULL,
  role                 text    NOT NULL DEFAULT 'staff',   -- 'staff' | 'admin'
  active               boolean NOT NULL DEFAULT true,
  must_reset_password  boolean NOT NULL DEFAULT true,
  can_view_all         boolean NOT NULL DEFAULT false,     -- see all sections' schedules
  can_create_groups    boolean NOT NULL DEFAULT false,     -- create & use meeting groups
  created_at timestamptz DEFAULT now()
);

-- Graceful upgrade: add new columns to existing staff table
ALTER TABLE staff ADD COLUMN IF NOT EXISTS can_view_all      boolean NOT NULL DEFAULT false;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS can_create_groups boolean NOT NULL DEFAULT false;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS can_request_users boolean NOT NULL DEFAULT false;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS telegram_chat_id  text;

-- Default system admin (login: SVC000 / Admin1234, forced to reset)
INSERT INTO staff (svc_no,name,email,password,role,active,must_reset_password,can_view_all,can_create_groups)
VALUES ('SVC000','System Admin','','Admin1234','admin',true,false,true,true)
ON CONFLICT (svc_no) DO NOTHING;

-- ─────────────────────────── MEETINGS ─────────────────────────────
CREATE TABLE IF NOT EXISTS meetings (
  id               serial  PRIMARY KEY,
  title            text    NOT NULL,
  type             text    NOT NULL DEFAULT 'internal',  -- 'internal' | 'external'
  meeting_mode     text    NOT NULL DEFAULT 'physical',  -- 'physical' | 'online' | 'both'
  meeting_link     text,
  privacy          text    NOT NULL DEFAULT 'public',    -- 'public' | 'private'
  date             date    NOT NULL,
  start_slot       integer NOT NULL,   -- 0 = 08:00, 1 = 08:30 …
  duration         integer NOT NULL DEFAULT 1,  -- half-hour slots
  notes            text,
  location         text,
  no_room          boolean DEFAULT false,        -- internal meeting without a room
  room_id          integer REFERENCES rooms(id),
  section_id       integer REFERENCES sections(id),
  section_name     text,
  created_by       integer REFERENCES staff(id),
  created_by_name  text,
  created_by_svc   text,
  created_at timestamptz DEFAULT now()
);

-- Graceful upgrade: add columns to existing meetings table
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS meeting_mode  text    DEFAULT 'physical';
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS meeting_link  text;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS no_room       boolean DEFAULT false;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS is_prebooked  boolean DEFAULT false;

-- ─────────────────────────── PARTICIPANTS ─────────────────────────
CREATE TABLE IF NOT EXISTS participants (
  id                     serial  PRIMARY KEY,
  meeting_id             integer REFERENCES meetings(id) ON DELETE CASCADE,
  staff_id               integer REFERENCES staff(id),
  name                   text    NOT NULL,
  email                  text,
  is_external            boolean DEFAULT false,
  rsvp                   text    DEFAULT 'pending',    -- 'pending' | 'accepted' | 'declined'
  rsvp_note              text,
  attendance             text,                         -- 'present' | 'absent' | 'late' | null
  attendance_note        text,
  attendance_marked_by   integer REFERENCES staff(id),
  attendance_marked_at   timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Graceful upgrade
ALTER TABLE participants ADD COLUMN IF NOT EXISTS attendance           text;
ALTER TABLE participants ADD COLUMN IF NOT EXISTS attendance_note      text;
ALTER TABLE participants ADD COLUMN IF NOT EXISTS attendance_marked_by integer REFERENCES staff(id);
ALTER TABLE participants ADD COLUMN IF NOT EXISTS attendance_marked_at timestamptz;

-- Graceful upgrade: add scheduled notification columns
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS scheduled_for      timestamptz;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sent_at            timestamptz;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS recipient_chat_id  text;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS telegram_message_id bigint;

-- ─────────────────────────── NOTIFICATIONS ────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id             serial PRIMARY KEY,
  meeting_id     integer REFERENCES meetings(id) ON DELETE CASCADE,
  participant_id integer REFERENCES participants(id) ON DELETE CASCADE,
  type           text DEFAULT 'invitation',   -- 'invitation' | 'update' | 'reminder' | 'cancellation'
  subject        text,
  body           text,
  status         text DEFAULT 'sent',
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────── MEETING GROUPS ───────────────────────
CREATE TABLE IF NOT EXISTS meeting_groups (
  id          serial PRIMARY KEY,
  name        text   NOT NULL,
  description text,
  created_by  integer REFERENCES staff(id),
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS meeting_group_members (
  id       serial  PRIMARY KEY,
  group_id integer REFERENCES meeting_groups(id) ON DELETE CASCADE,
  staff_id integer REFERENCES staff(id)          ON DELETE CASCADE,
  UNIQUE(group_id, staff_id)
);

-- Per-group access: which staff can select this group when scheduling
CREATE TABLE IF NOT EXISTS meeting_group_access (
  group_id integer REFERENCES meeting_groups(id) ON DELETE CASCADE,
  staff_id integer REFERENCES staff(id)          ON DELETE CASCADE,
  PRIMARY KEY (group_id, staff_id)
);
ALTER TABLE meeting_group_access DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS grp_access_group_idx ON meeting_group_access(group_id);
CREATE INDEX IF NOT EXISTS grp_access_staff_idx ON meeting_group_access(staff_id);

-- ─────────────────────────── ROW LEVEL SECURITY ──────────────────
-- This app authenticates in JavaScript using the anon key.
-- Disable RLS on all tables so anon key requests are not blocked.
ALTER TABLE sections             DISABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                DISABLE ROW LEVEL SECURITY;
ALTER TABLE staff                DISABLE ROW LEVEL SECURITY;
ALTER TABLE meetings             DISABLE ROW LEVEL SECURITY;
ALTER TABLE participants         DISABLE ROW LEVEL SECURITY;
ALTER TABLE notifications        DISABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_groups       DISABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_group_members DISABLE ROW LEVEL SECURITY;

-- ─────────────────────────── INDEXES ──────────────────────────────
CREATE INDEX IF NOT EXISTS meetings_date_idx           ON meetings(date);
CREATE INDEX IF NOT EXISTS meetings_room_date_idx      ON meetings(room_id, date);
CREATE INDEX IF NOT EXISTS participants_meeting_idx    ON participants(meeting_id);
CREATE INDEX IF NOT EXISTS participants_staff_idx      ON participants(staff_id);
CREATE INDEX IF NOT EXISTS grp_members_group_idx       ON meeting_group_members(group_id);
CREATE INDEX IF NOT EXISTS grp_members_staff_idx       ON meeting_group_members(staff_id);

-- ─────────────────────────── RECURRING MEETINGS ──────────────────
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS recurrence_id   text;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS recurrence_rule text;

-- ─────────────────────────── CANCELLATION ────────────────────────
-- Meetings are never deleted; cancelling sets is_cancelled = true.
-- Cancelled meetings are excluded from calendar/room slot queries.
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS is_cancelled      boolean DEFAULT false;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS cancelled_at      timestamptz;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS cancelled_reason  text;

-- ─────────────────────────── MEETING LOCK ─────────────────────────
-- Creator can lock a meeting to prevent edits/cancellations by anyone
-- except admin. Creator can unlock at any time.
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS is_locked boolean DEFAULT false;

-- ─────────────────────────── MEETING NOTES ────────────────────────
ALTER TABLE meetings     ADD COLUMN IF NOT EXISTS minutes              text;
ALTER TABLE meetings     ADD COLUMN IF NOT EXISTS minutes_updated_at   timestamptz;
ALTER TABLE meetings     ADD COLUMN IF NOT EXISTS minutes_updated_by   integer REFERENCES staff(id);
ALTER TABLE meetings     ADD COLUMN IF NOT EXISTS minutes_finalized    boolean DEFAULT false;
ALTER TABLE participants ADD COLUMN IF NOT EXISTS personal_notes       text;

-- ─────────────────────────── ROOM BLOCKS ──────────────────────────
CREATE TABLE IF NOT EXISTS room_blocks (
  id        serial  PRIMARY KEY,
  room_id   integer REFERENCES rooms(id) ON DELETE CASCADE,
  date_from date    NOT NULL,
  date_to   date    NOT NULL,
  reason    text,
  created_by integer REFERENCES staff(id),
  created_at timestamptz DEFAULT now()
);
ALTER TABLE room_blocks DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS room_blocks_room_idx ON room_blocks(room_id);

-- Staff rank and designation
ALTER TABLE staff ADD COLUMN IF NOT EXISTS rank_short  text;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS designation text;

-- Staff leaves
CREATE TABLE IF NOT EXISTS staff_leaves (
  id         serial  PRIMARY KEY,
  staff_id   integer REFERENCES staff(id) ON DELETE CASCADE,
  leave_type text    NOT NULL,
  date_from  date    NOT NULL,
  date_to    date    NOT NULL,
  notes      text,
  created_by integer REFERENCES staff(id),
  created_at timestamptz DEFAULT now()
);
ALTER TABLE staff_leaves DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS staff_leaves_staff_idx ON staff_leaves(staff_id);
CREATE INDEX IF NOT EXISTS staff_leaves_dates_idx ON staff_leaves(date_from, date_to);

-- ─────────────────────────── MULTI-SECTION ACCESS ────────────────
-- Allows a staff member to view and manage meetings for extra sections
-- beyond their primary section_id (e.g. supervisors overseeing multiple units).
CREATE TABLE IF NOT EXISTS staff_sections (
  staff_id   integer REFERENCES staff(id)    ON DELETE CASCADE,
  section_id integer REFERENCES sections(id) ON DELETE CASCADE,
  PRIMARY KEY (staff_id, section_id)
);
ALTER TABLE staff_sections DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS staff_sections_staff_idx ON staff_sections(staff_id);

-- ─────────────────────────── STAFF REQUESTS ─────────────────────
-- New user requests and password reset requests submitted by staff.
CREATE TABLE IF NOT EXISTS staff_requests (
  id               serial  PRIMARY KEY,
  type             text    NOT NULL,   -- 'new_user' | 'password_reset'
  status           text    NOT NULL DEFAULT 'pending',  -- 'pending' | 'approved' | 'rejected'
  -- New user fields
  req_svc_no       text,
  req_name         text,
  req_email        text,
  req_rank_short   text,
  req_designation  text,
  req_section_id   integer REFERENCES sections(id),
  req_telegram_chat_id text,
  req_notes        text,
  -- Password reset fields
  target_staff_id  integer REFERENCES staff(id),
  -- Common
  requested_by     integer REFERENCES staff(id),
  created_at       timestamptz DEFAULT now(),
  processed_by     integer REFERENCES staff(id),
  processed_at     timestamptz,
  admin_response   text
);
ALTER TABLE staff_requests DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS staff_requests_status_idx ON staff_requests(status);

-- ─────────────────────────── APP CONFIG ──────────────────────────
-- Generic key-value store for app-wide settings (e.g. Telegram bot token).
-- Storing here means the setting is shared across all browsers/devices.
CREATE TABLE IF NOT EXISTS app_config (
  key        text PRIMARY KEY,
  value      text,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE app_config DISABLE ROW LEVEL SECURITY;

-- ─────────────────────────── STEP 2: ENABLE RLS (run after Edge Function is deployed) ──────────
-- Run this block AFTER deploying supabase/functions/meetflow-login.
-- It closes direct anon-key access to all tables and requires a valid
-- JWT (issued by the Edge Function) for every PostgREST request.
--
-- Deploy steps:
--   1. supabase login
--   2. supabase link --project-ref <your-project-ref>
--   3. Add secret in dashboard: Name = MF_JWT_SECRET, Value = JWT secret from Settings → API → JWT Keys
--   4. supabase functions deploy meetflow-login
--   5. Run this SQL block in the Supabase SQL Editor

-- Grant the authenticated Postgres role full access to all tables
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Enable RLS (overrides the DISABLE statements above for each table)
ALTER TABLE sections              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE meetings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants          ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications         ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_groups        ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE meeting_group_access  ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_blocks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_leaves          ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_sections        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config            ENABLE ROW LEVEL SECURITY;

-- Create permissive policies for the authenticated role.
-- The anon key (browser) now requires a valid JWT from the Edge Function.
-- Finer per-row restrictions can be added here later without app changes.
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['sections','rooms','staff','meetings','participants',
    'notifications','meeting_groups','meeting_group_members','meeting_group_access',
    'room_blocks','staff_leaves','staff_sections','app_config']::text[] LOOP
    EXECUTE format('DROP POLICY IF EXISTS auth_all ON %I', tbl);
    EXECUTE format(
      'CREATE POLICY auth_all ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)',
      tbl
    );
  END LOOP;
END $$;

-- Revoke direct anon access — the anon key is only used to invoke the Edge Function
REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;

-- ─────────────────────────── DONE ─────────────────────────────────
-- After running the base schema, open the app, paste your Supabase URL + anon key,
-- then sign in with service number SVC000 / Admin1234.
-- After deploying the Edge Function and running Step 2, direct DB access
-- via the anon key is blocked — all requests require a valid login JWT.
