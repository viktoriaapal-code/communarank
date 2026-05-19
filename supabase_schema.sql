-- ============================================================
-- CommunaRank Database Schema
-- Run this in Supabase SQL Editor: supabase.com → your project → SQL Editor
-- ============================================================

-- 1. REVIEWS TABLE
-- Stores all resident community reviews
CREATE TABLE IF NOT EXISTS reviews (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  community     TEXT NOT NULL,
  canton        TEXT NOT NULL,
  overall       INTEGER NOT NULL CHECK (overall BETWEEN 1 AND 5),
  name          TEXT NOT NULL,
  text          TEXT DEFAULT '',
  tags          TEXT[] DEFAULT '{}',
  bfs_number    INTEGER,
  pros          TEXT,
  cons          TEXT,
  years         TEXT,
  profile       TEXT,
  tenure        TEXT CHECK (tenure IN ('owner', 'renter', '')),
  proptype      TEXT,
  ratings       JSONB DEFAULT '{}',
  helpful       INTEGER DEFAULT 0,
  lang          TEXT DEFAULT 'en',
  status        TEXT DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast community lookups
CREATE INDEX IF NOT EXISTS reviews_community_idx ON reviews(community);
CREATE INDEX IF NOT EXISTS reviews_canton_idx ON reviews(canton);
CREATE INDEX IF NOT EXISTS reviews_status_idx ON reviews(status);
CREATE INDEX IF NOT EXISTS reviews_created_idx ON reviews(created_at DESC);
CREATE INDEX IF NOT EXISTS reviews_bfs_number_idx ON reviews(bfs_number);

-- 1b. REVIEW_TAGS TABLE (quick-tag options for the review form)
CREATE TABLE IF NOT EXISTS review_tags (
  id            SERIAL PRIMARY KEY,
  slug          TEXT NOT NULL UNIQUE,
  label_en      TEXT NOT NULL,
  label_fr      TEXT,
  label_de      TEXT,
  label_it      TEXT,
  sort_order    INTEGER DEFAULT 0,
  active        BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS review_tags_active_idx ON review_tags(active, sort_order);

-- 2. WAITLIST TABLE
-- Stores early access signups
CREATE TABLE IF NOT EXISTS waitlist (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name          TEXT NOT NULL,
  email         TEXT NOT NULL UNIQUE,
  canton        TEXT,
  budget        TEXT,
  goals         TEXT,
  lang          TEXT DEFAULT 'en',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS waitlist_email_idx ON waitlist(email);

-- 3. COMMUNITIES TABLE
-- Stores the official data index scores (replaces communities.json)
CREATE TABLE IF NOT EXISTS communities (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name           TEXT NOT NULL UNIQUE,
  bfs_number     INTEGER,
  canton         TEXT NOT NULL,
  type           TEXT,
  population     INTEGER,
  land_price     INTEGER,
  lat            DECIMAL(8,4),
  lon            DECIMAL(8,4),
  scores         JSONB NOT NULL DEFAULT '{}',
  median_income  INTEGER,
  avg_income     INTEGER,
  salary_ratio   INTEGER,
  tags           TEXT[] DEFAULT '{}',
  data_source    TEXT DEFAULT 'BFS+ELCOM+OSM',
  last_updated   DATE DEFAULT CURRENT_DATE,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS communities_name_idx ON communities(name);
CREATE INDEX IF NOT EXISTS communities_canton_idx ON communities(canton);

-- 4. ALL_COMMUNES TABLE
-- Complete list of all 2131 Swiss municipalities for review autocomplete
CREATE TABLE IF NOT EXISTS all_communes (
  bfs_number    INTEGER PRIMARY KEY,
  name          TEXT NOT NULL,
  canton        TEXT NOT NULL,
  canton_code   CHAR(2) NOT NULL,
  active        BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS communes_name_idx ON all_communes(name);
CREATE INDEX IF NOT EXISTS communes_canton_code_idx ON all_communes(canton_code);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) — Critical for production!
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE communities ENABLE ROW LEVEL SECURITY;
ALTER TABLE all_communes ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_tags ENABLE ROW LEVEL SECURITY;

-- REVIEWS: anyone can read approved reviews, anyone can insert
CREATE POLICY "Anyone can read approved reviews"
  ON reviews FOR SELECT
  USING (status = 'approved');

CREATE POLICY "Anyone can insert reviews"
  ON reviews FOR INSERT
  WITH CHECK (true);

-- Only service role (your backend) can update/delete
CREATE POLICY "Service role can manage reviews"
  ON reviews FOR ALL
  USING (auth.role() = 'service_role');

-- WAITLIST: only service role can read (GDPR), anyone can insert
CREATE POLICY "Service role can read waitlist"
  ON waitlist FOR SELECT
  USING (auth.role() = 'service_role');

CREATE POLICY "Anyone can join waitlist"
  ON waitlist FOR INSERT
  WITH CHECK (true);

-- COMMUNITIES: public read, service role write
CREATE POLICY "Public can read communities"
  ON communities FOR SELECT
  USING (true);

CREATE POLICY "Service role manages communities"
  ON communities FOR ALL
  USING (auth.role() = 'service_role');

-- ALL_COMMUNES: public read only
CREATE POLICY "Public can read communes"
  ON all_communes FOR SELECT
  USING (true);

-- REVIEW_TAGS: public read active tags only
CREATE POLICY "Public can read active review tags"
  ON review_tags FOR SELECT
  USING (active = true);

-- ============================================================
-- HELPFUL VIEWS
-- ============================================================

-- Community review summary (for People's Ranking)
CREATE OR REPLACE VIEW community_review_summary AS
SELECT
  community,
  canton,
  COUNT(*) as review_count,
  ROUND(AVG(overall), 2) as avg_rating,
  ROUND(AVG(overall) * 20) as score_out_of_100
FROM reviews
WHERE status = 'approved'
GROUP BY community, canton
ORDER BY avg_rating DESC;

-- Top reviewed cantons
CREATE OR REPLACE VIEW canton_review_summary AS
SELECT
  canton,
  COUNT(*) as review_count,
  ROUND(AVG(overall), 2) as avg_rating
FROM reviews
WHERE status = 'approved'
GROUP BY canton
ORDER BY review_count DESC;

-- ============================================================
-- RATE LIMITING FUNCTION (basic spam protection)
-- ============================================================
CREATE OR REPLACE FUNCTION check_review_rate_limit(p_community TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  recent_count INTEGER;
BEGIN
  -- Max 3 reviews per community per hour from the same session
  SELECT COUNT(*) INTO recent_count
  FROM reviews
  WHERE community = p_community
    AND created_at > NOW() - INTERVAL '1 hour';

  RETURN recent_count < 10; -- allow max 10 reviews per community per hour
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- NEXT STEPS (after running this schema):
-- 1. Go to Supabase → Settings → API
-- 2. Copy your "anon/public" key and "Project URL"
-- 3. Create a .env file or Vercel environment variable:
--    NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
--    NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
-- 4. Update the submitReview() and submitWaitlist() functions
--    in index.html to POST to Supabase REST API
-- ============================================================
