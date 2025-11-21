const express = require("express");
const cors = require("cors");
const { Pool } = require("pg");

const app = express();
app.use(cors());

// PostgreSQL connection
const pool = new Pool({
  host: "localhost",
  user: "postgres",
  password: "your_password",
  database: "your_database",
  port: 5432
});

// ===============================
// 1. Trend Chart API
// ===============================
app.get("/api/engagement/trend", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        DATE_TRUNC('month', engaged_timestamp) AS month,
        a.name AS author,
        COUNT(*) AS total_engagements
      FROM engagements e
      JOIN posts p ON p.post_id = e.post_id
      JOIN authors a ON a.author_id = p.author_id
      GROUP BY month, author
      ORDER BY month;
    `);

    res.json(result.rows);
  } catch (err) {
    res.status(500).send(err.message);
  }
});

// ===============================
// 2. Heatmap API (hour x day)
// ===============================
app.get("/api/engagement/heatmap", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        EXTRACT(DOW FROM engaged_timestamp) AS day_of_week,
        EXTRACT(HOUR FROM engaged_timestamp) AS hour,
        COUNT(*) AS engagement_count
      FROM engagements
      GROUP BY day_of_week, hour
      ORDER BY day_of_week, hour;
    `);

    res.json(result.rows);
  } catch (err) {
    res.status(500).send(err.message);
  }
});

// ===============================
// 3. Scatter Plot API
// ===============================
app.get("/api/engagement/scatter", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        a.author_id,
        a.name AS author_name,
        COUNT(DISTINCT p.post_id) AS post_volume,
        COUNT(e.engagement_id) AS total_engagements,
        ROUND(COUNT(e.engagement_id)::numeric 
        / NULLIF(COUNT(DISTINCT p.post_id), 0), 2) 
          AS engagement_per_post
      FROM authors a
      LEFT JOIN posts p ON a.author_id = p.author_id
      LEFT JOIN engagements e ON p.post_id = e.post_id
      GROUP BY a.author_id, a.name;
    `);

    res.json(result.rows);
  } catch (err) {
    res.status(500).send(err.message);
  }
});

// -------------------------------------------
// Trend API: last 7 days vs previous 7 days
// -------------------------------------------
app.get("/api/engagement/trend", async (req, res) => {
  const { author_id, post_id } = req.query;

  // Build WHERE clause dynamically
  let filter = "";
  const params = [];

  if (author_id) {
    filter = "AND p.author_id = $1";
    params.push(author_id);
  }
  else if (post_id) {
    filter = "AND e.post_id = $1";
    params.push(post_id);
  }

  const query = `
        WITH last7 AS (
            SELECT COUNT(*) AS count
            FROM engagements e
            JOIN posts p ON p.post_id = e.post_id
            WHERE engaged_timestamp >= NOW() - INTERVAL '7 days'
            ${filter}
        ),
        prev7 AS (
            SELECT COUNT(*) AS count
            FROM engagements e
            JOIN posts p ON p.post_id = e.post_id
            WHERE engaged_timestamp < NOW() - INTERVAL '7 days'
              AND engaged_timestamp >= NOW() - INTERVAL '14 days'
            ${filter}
        )
        SELECT 
            (SELECT count FROM last7) AS last_7_days,
            (SELECT count FROM prev7) AS prev_7_days,
            CASE 
                WHEN (SELECT count FROM prev7) = 0 THEN NULL
                ELSE ROUND(
                    ((SELECT count FROM last7) - (SELECT count FROM prev7))::numeric 
                    / (SELECT count FROM prev7) * 100,
                2)
            END AS pct_change
    `;

  const result = await pool.query(query, params);
  res.json(result.rows[0]);
});


// Start server
app.listen(3000, () => console.log("API running on port 3000"));
