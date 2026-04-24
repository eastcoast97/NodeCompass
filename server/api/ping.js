module.exports = (req, res) => {
  res.json({ ping: "pong", time: Date.now() });
};
