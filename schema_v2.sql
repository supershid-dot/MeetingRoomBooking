-- Meeting Scheduler — schema_v2.sql
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

-- ─────────────────────────── INDEXES ──────────────────────────────
CREATE INDEX IF NOT EXISTS meetings_date_idx           ON meetings(date);
CREATE INDEX IF NOT EXISTS meetings_room_date_idx      ON meetings(room_id, date);
CREATE INDEX IF NOT EXISTS participants_meeting_idx    ON participants(meeting_id);
CREATE INDEX IF NOT EXISTS participants_staff_idx      ON participants(staff_id);
CREATE INDEX IF NOT EXISTS grp_members_group_idx       ON meeting_group_members(group_id);
CREATE INDEX IF NOT EXISTS grp_members_staff_idx       ON meeting_group_members(staff_id);

-- ─────────────────────────── DONE ─────────────────────────────────
-- After running this, open the app, paste your Supabase URL + anon key,
-- then sign in with service number SVC000 / Admin1234.
