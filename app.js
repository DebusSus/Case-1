const express = require('express');
const mysql = require('mysql2');
const path = require('path');
const app = express();
const port = 3000;

// RDS connection details - will be set by ECS environment variables
const connection = mysql.createConnection({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'admin',
  password: process.env.DB_PASSWORD || 'dariusdbpass876',
  database: process.env.DB_NAME || 'ticketdb'
});

// Connect to RDS
connection.connect((err) => {
  if (err) {
    console.error('Error connecting to RDS: ' + err.stack);
    return;
  }
  console.log('Connected to RDS as id ' + connection.threadId);
});

// Create tickets table if not exists
connection.query(`
  CREATE TABLE IF NOT EXISTS tickets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    purchase_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
`, (err) => {
  if (err) console.error('Error creating table: ' + err);
});

// IMPORTANT: Static middleware FIRST, before any routes
app.use(express.static(path.join(__dirname, 'public')));

// API routes (after static middleware)
app.post('/buy', express.json(), (req, res) => {
  connection.query('INSERT INTO tickets (purchase_time) VALUES (NOW())', (err, results) => {
    if (err) {
      console.error('Error inserting ticket: ' + err);
      res.status(500).json({ success: false, message: 'Error buying ticket' });
    } else {
      res.json({ success: true, message: 'Ticket purchased successfully!', ticketId: results.insertId });
    }
  });
});

app.get('/api/tickets', (req, res) => {
  res.json([
    { id: 1, event: 'Concert Night', price: 25, available: 100 },
    { id: 2, event: 'Tech Conference', price: 50, available: 75 },
    { id: 3, event: 'Movie Premiere', price: 15, available: 200 }
  ]);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Catch-all route LAST (after static middleware)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start the server
app.listen(port, () => {
  console.log(`Ticket app running on port ${port}`);
  console.log(`Access at: http://localhost:${port}`);
});