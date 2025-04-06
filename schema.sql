PRAGMA foreign_keys = ON;

-- Users Table
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- Posts Table (with embedded media)
CREATE TABLE posts (
    post_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    post_type TEXT NOT NULL CHECK (post_type IN ('text', 'image', 'video')),
    media_url TEXT,
    media_type TEXT CHECK (media_type IN ('image', 'video')),
    alt_text TEXT,
    thumbnail_url TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    parent_post_id INTEGER REFERENCES posts(post_id),
    
    -- Media validation constraint
    CHECK (
        (post_type = 'text' AND media_url IS NULL) OR
        (post_type IN ('image', 'video') AND media_url IS NOT NULL)
    )
);

-- Tags Table
CREATE TABLE tags (
    tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
    tag_name TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER DEFAULT 0
);

-- Post-Tags Junction Table
CREATE TABLE post_tags (
    post_id INTEGER REFERENCES posts(post_id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(tag_id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);

-- Interactions Table
CREATE TABLE interactions (
    interaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    post_id INTEGER NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
    interaction_type TEXT NOT NULL CHECK (
        interaction_type IN ('comment', 'reribb', 'like', 'rsvp')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    content TEXT,
    UNIQUE(user_id, post_id, interaction_type)
);

-- Events Table
CREATE TABLE events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER UNIQUE REFERENCES posts(post_id) ON DELETE CASCADE,
    event_time DATETIME NOT NULL,
    location TEXT NOT NULL,
    host_org TEXT,
    rsvp_count INTEGER DEFAULT 0,
    max_capacity INTEGER
);

-- Authentication Table
CREATE TABLE auth (
    user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    password_hash TEXT NOT NULL,
    last_login DATETIME,
    reset_token TEXT,
    token_expiry DATETIME
);

-- Indexes
CREATE INDEX idx_posts_created ON posts(created_at);
CREATE INDEX idx_posts_type ON posts(post_type);
CREATE INDEX idx_interactions_type ON interactions(interaction_type);
CREATE INDEX idx_tags_name ON tags(tag_name);
CREATE INDEX idx_events_time ON events(event_time);

-- Trending Ponds View (Updated hourly via application logic)
CREATE VIEW trending_ponds AS
SELECT t.tag_id, t.tag_name, COUNT(pt.post_id) AS recent_posts
FROM tags t
JOIN post_tags pt ON t.tag_id = pt.tag_id
JOIN posts p ON pt.post_id = p.post_id
WHERE p.created_at > datetime('now', '-1 day')
GROUP BY t.tag_id
ORDER BY recent_posts DESC
LIMIT 10;
