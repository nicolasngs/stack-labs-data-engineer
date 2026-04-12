require('dotenv').config({ path: '../.env' });
//const expectedApiKey = process.env.API_KEY;

module.exports = (req, res, next) => {
  //const apiKey = req.header('X-API-KEY');
  
  // Verifie la cle API
  //if (!apiKey || apiKey !== expectedApiKey) {
  //  return res.status(401).json({ error: "Unauthorized: Invalid API Key" });
  //}

  // Verifie la limite pour la page
  if (req.query._limit || req.query.limit) {
    req.query._limit = "4";
  }

  next();
};
