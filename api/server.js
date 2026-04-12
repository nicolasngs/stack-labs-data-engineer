require('dotenv').config({ path: '../.env' });
const express = require('express');
const apiData = require('./api.json');
const authMiddleware = require('./middleware');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(authMiddleware);

app.get('/customers', (req, res) => {
  res.json(apiData.customers);
});

app.get('/products', (req, res) => {
  res.json(apiData.products);
});

app.get('/sales', (req, res) => {
  res.json(apiData.sales);
});

app.listen(PORT, () => {
  console.log(`API running on http://localhost:${PORT}`);
});
