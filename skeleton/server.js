/**
 * RHDH Demo Application - Node.js Server
 * A simple Express server for Backstage scaffolder demos
 */

const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Serve static files from public directory
app.use(express.static(path.join(__dirname, 'public')));

// Health check endpoint
app.get('/health', (_, res) => {
  res.json({
    status: 'UP',
    service: 'RHDH Demo Application',
    timestamp: new Date().toISOString(),
  });
});

// Readiness probe endpoint
app.get('/ready', (_, res) => {
  res.json({
    status: 'UP',
    ready: true,
  });
});

// Environment endpoint - returns current environment from APP_ENV
app.get('/env', (_, res) => {
  res.json({
    environment: process.env.APP_ENV || 'dev',
  });
});

app.listen(PORT, () => {
  console.log(`RHDH Demo app running on http://localhost:${PORT}`);
  console.log(`Environment: ${process.env.APP_ENV || 'dev'}`);
});
