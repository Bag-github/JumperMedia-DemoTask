-- ============================================
-- 1. ENUM Types
-- ============================================
CREATE TYPE engagement_type AS ENUM ('view', 'like', 'comment', 'share');

-- ============================================
-- 2. Authors Table with BIGINT + sequence
-- ============================================
CREATE SEQUENCE authors_id_seq START WITH 1 INCREMENT BY 1 CACHE 1000;

CREATE TABLE authors (
    author_id BIGINT PRIMARY KEY DEFAULT nextval('authors_id_seq'),
    name TEXT NOT NULL,
    joined_date DATE NOT NULL DEFAULT CURRENT_DATE,
    author_category TEXT NOT NULL,
    CONSTRAINT chk_author_category CHECK (char_length(author_category) > 0)
);

COMMENT ON TABLE authors IS 'Stores all authors who create posts';

-- Index for analytics
CREATE INDEX idx_authors_category ON authors(author_category);

-- ============================================
-- 3. Users Table with BIGINT + sequence
-- ============================================
CREATE SEQUENCE users_id_seq START WITH 1 INCREMENT BY 1 CACHE 1000;

CREATE TABLE users (
    user_id BIGINT PRIMARY KEY DEFAULT nextval('users_id_seq'),
    signup_date DATE NOT NULL DEFAULT CURRENT_DATE,
    country TEXT,
    user_segment TEXT
);

COMMENT ON TABLE users IS 'Stores user demographic + segmentation info';

-- Index for cohort analysis
CREATE INDEX idx_users_segment ON users(user_segment);

-- ============================================
-- 4. Posts Table with BIGINT + sequence
-- ============================================
CREATE SEQUENCE posts_id_seq START WITH 1 INCREMENT BY 1 CACHE 1000;

CREATE TABLE posts (
    post_id BIGINT PRIMARY KEY DEFAULT nextval('posts_id_seq'),
    author_id BIGINT NOT NULL REFERENCES authors(author_id),
    category TEXT NOT NULL,
    publish_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    title TEXT NOT NULL,
    content_length INT NOT NULL,
    has_media BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE posts IS 'Core table: one row per published post';

-- Indexes for analytics
CREATE INDEX idx_posts_published_ts ON posts(publish_timestamp);
CREATE INDEX idx_posts_author_category ON posts(author_id, category);

-- ============================================
-- 5. Post Metadata Table
-- ============================================
CREATE TABLE post_metadata (
    post_id BIGINT PRIMARY KEY REFERENCES posts(post_id),
    tags TEXT[],
    is_promoted BOOLEAN NOT NULL DEFAULT FALSE,
    language TEXT
);

COMMENT ON TABLE post_metadata IS 'Optional extra metadata per post';

-- Indexes
CREATE INDEX idx_metadata_promoted ON post_metadata(is_promoted);
CREATE INDEX idx_metadata_tags ON post_metadata USING GIN (tags);

-- ============================================
-- 6. Engagements Table (Partitioned) with BIGINT + sequence
-- ============================================
CREATE SEQUENCE engagements_id_seq START WITH 1 INCREMENT BY 1 CACHE 10000;

CREATE TABLE engagements (
    engagement_id BIGINT NOT NULL DEFAULT nextval('engagements_id_seq'),
    post_id BIGINT NOT NULL,
    type engagement_type NOT NULL,
    user_id BIGINT,
    engaged_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (engagement_id, engaged_timestamp, post_id)
) PARTITION BY RANGE (engaged_timestamp);

COMMENT ON TABLE engagements IS 'High-volume table partitioned by month for scalability';

-- ============================================
-- 7. Partitions (Monthly)
-- ============================================
CREATE TABLE engagements_2025_11 PARTITION OF engagements
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE engagements_2025_12 PARTITION OF engagements
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- Indexes per partition
CREATE INDEX idx_engagements_2025_11_post_id ON engagements_2025_11(post_id);
CREATE INDEX idx_engagements_2025_11_post_type ON engagements_2025_11(post_id, type);

CREATE INDEX idx_engagements_2025_12_post_id ON engagements_2025_12(post_id);
CREATE INDEX idx_engagements_2025_12_post_type ON engagements_2025_12(post_id, type);


-- ============================================
-- Insert Authors
-- ============================================
INSERT INTO authors (name, joined_date, author_category) VALUES
('Alice', '2020-01-14', 'Tech'),
('Bob', '2019-06-30', 'Lifestyle'),
('Carlos', '2021-11-05', 'Tech');

-- ============================================
-- Insert Users
-- ============================================
INSERT INTO users (signup_date, country, user_segment) VALUES
('2025-01-10', 'US', 'free'),
('2025-02-12', 'UK', 'subscriber'),
('2024-12-05', 'US', 'trial');

-- ============================================
-- Insert Posts
-- ============================================
-- Note: author_id must match the generated IDs in authors table
-- If you want to guarantee IDs, use RETURNING clause to fetch them
INSERT INTO posts (author_id, category, publish_timestamp, title, content_length, has_media) VALUES
(1, 'Tech', '2025-08-01 10:15:00', 'Deep Dive into X', 1200, TRUE),
(2, 'Lifestyle', '2025-08-02 17:30:00', '5 Morning Routines', 800, FALSE),
(3, 'Tech', '2025-08-03 08:45:00', 'Why we love SQL', 950, TRUE);

-- ============================================
-- Insert Engagements
-- ============================================
-- Note: post_id and user_id must match previously inserted posts and users
INSERT INTO engagements (post_id, type, user_id, engaged_timestamp) VALUES
(1, 'view', 1, '2025-11-01 10:16:00'),
(1, 'like', 2, '2025-11-01 10:17:00'),
(2, 'comment', 3, '2025-11-02 17:45:00'),
(1, 'share', 4, '2025-11-01 11:00:00'),
(3, 'view', 5, '2025-11-03 09:00:00');


-- ============================================
-- Insert Post Metadata
-- ============================================
INSERT INTO post_metadata (post_id, tags, is_promoted, language) VALUES
(1, ARRAY['SQL','Optimization'], FALSE, 'en'),
(2, ARRAY['Wellness','Morning'], TRUE, 'en'),
(3, ARRAY['SQL','Postgres','Tips'], FALSE, 'en');



--Analysis & Queries

--Part A
-- Top authors by engagement in the last month
SELECT 
    a.author_id,
    a.name AS author_name,
    COUNT(e.engagement_id) AS total_engagements,
    SUM(CASE WHEN e.type = 'view' THEN 1 ELSE 0 END) AS views,
    SUM(CASE WHEN e.type = 'like' THEN 1 ELSE 0 END) AS likes,
    SUM(CASE WHEN e.type = 'share' THEN 1 ELSE 0 END) AS shares
FROM engagements e
JOIN posts p ON e.post_id = p.post_id
JOIN authors a ON p.author_id = a.author_id
WHERE e.engaged_timestamp >= NOW() - INTERVAL '1 month'
GROUP BY a.author_id, a.name
ORDER BY total_engagements DESC
LIMIT 10;

-- Top categories by engagement in the last 3 months
SELECT 
    p.category,
    COUNT(e.engagement_id) AS total_engagements,
    SUM(CASE WHEN e.type = 'view' THEN 1 ELSE 0 END) AS views,
    SUM(CASE WHEN e.type = 'like' THEN 1 ELSE 0 END) AS likes,
    SUM(CASE WHEN e.type = 'share' THEN 1 ELSE 0 END) AS shares
FROM engagements e
JOIN posts p ON e.post_id = p.post_id
WHERE e.engaged_timestamp >= NOW() - INTERVAL '3 months'
GROUP BY p.category
ORDER BY total_engagements DESC;


--Part B
-- Engagements by hour of day
SELECT 
    EXTRACT(HOUR FROM e.engaged_timestamp) AS hour_of_day,
    COUNT(*) AS total_engagements
FROM engagements e
WHERE e.engaged_timestamp >= NOW() - INTERVAL '1 month'
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Engagements by day of week
SELECT *
FROM (
    SELECT 
        TO_CHAR(engaged_timestamp, 'Day') AS day_of_week,
        EXTRACT(DOW FROM engaged_timestamp) AS day_number,  -- 0=Sunday, 1=Monday...
        COUNT(*) AS total_engagements
    FROM engagements
    WHERE engaged_timestamp >= NOW() - INTERVAL '1 month'
    GROUP BY day_of_week, day_number
) AS sub
ORDER BY day_number;



--Part C
-- Low-engagement authors
SELECT 
    a.author_id,
    a.name AS author_name,
    COUNT(p.post_id) AS total_posts,
    COUNT(e.engagement_id) AS total_engagements,
    ROUND(COUNT(e.engagement_id)::numeric / NULLIF(COUNT(p.post_id),0), 2) AS avg_engagement_per_post
FROM posts p
JOIN authors a ON p.author_id = a.author_id
LEFT JOIN engagements e ON e.post_id = p.post_id
WHERE p.publish_timestamp >= NOW() - INTERVAL '3 months'
GROUP BY a.author_id, a.name
HAVING COUNT(p.post_id) > 5  -- high posting volume threshold
   AND (COUNT(e.engagement_id)::numeric / NULLIF(COUNT(p.post_id),0)) < 10  -- low avg engagement
ORDER BY avg_engagement_per_post ASC;


-- Low-engagement categories
SELECT 
    p.category,
    COUNT(p.post_id) AS total_posts,
    COUNT(e.engagement_id) AS total_engagements,
    ROUND(COUNT(e.engagement_id)::numeric / NULLIF(COUNT(p.post_id),0), 2) AS avg_engagement_per_post
FROM posts p
LEFT JOIN engagements e ON e.post_id = p.post_id
WHERE p.publish_timestamp >= NOW() - INTERVAL '3 months'
GROUP BY p.category
HAVING COUNT(p.post_id) > 10  -- high posting volume threshold
   AND ROUND(COUNT(e.engagement_id)::numeric / NULLIF(COUNT(p.post_id),0), 2) < 10  -- low avg engagement
ORDER BY avg_engagement_per_post ASC;

