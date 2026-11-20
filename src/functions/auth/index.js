// auth-login：用户登录，校验密码并签发 JWT（POST /auth/login）
// 用户数据存 GeminiDB Cassandra users 表，密码为 HMAC-SHA256 加盐哈希
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const cassandra = require('cassandra-driver');

let client = null;
function getClient() {
  if (!client) {
    client = new cassandra.Client({
      contactPoints: (process.env.CASSANDRA_HOSTS || '').split(',').filter(Boolean),
      port: parseInt(process.env.CASSANDRA_PORT || '9042', 10),
      localDataCenter: process.env.CASSANDRA_DC || 'datacenter1',
      keyspace: process.env.CASSANDRA_KEYSPACE || 'booksdemo',
      authProvider: new cassandra.auth.PlainTextAuthProvider(
        process.env.CASSANDRA_USERNAME || 'root',
        process.env.CASSANDRA_PASSWORD || ''
      ),
    });
  }
  return client;
}

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES = parseInt(process.env.JWT_EXPIRES || '3600', 10);

function hashPassword(password, salt) {
  return crypto.createHmac('sha256', salt).update(password).digest('hex');
}

exports.handler = async (event, context) => {
  try {
    const body = JSON.parse(event.body || '{}');
    const { username, password } = body;
    if (!username || !password) {
      return { statusCode: 400, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: 'username and password are required' }) };
    }

    const rs = await getClient().execute(
      'SELECT username, salt, password_hash, email FROM users WHERE username = ?',
      [username],
      { prepare: true }
    );
    const user = rs.first();

    if (!user) {
      return { statusCode: 401, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: 'invalid credentials' }) };
    }

    const actual = hashPassword(password, user.salt);
    if (actual !== user.password_hash) {
      return { statusCode: 401, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: 'invalid credentials' }) };
    }

    const token = jwt.sign(
      { sub: username, email: user.email || username, scope: 'email' },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES }
    );

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, token_type: 'Bearer', expires_in: JWT_EXPIRES }),
    };
  } catch (e) {
    console.error('auth error:', e);
    return { statusCode: 500, headers: {}, body: JSON.stringify({ message: 'internal error' }) };
  }
};
