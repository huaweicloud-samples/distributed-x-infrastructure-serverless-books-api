// 初始化 GeminiDB Cassandra keyspace/表结构 + 默认用户
// 用法见 init-tables.sh
const crypto = require('crypto');
const cassandra = require('cassandra-driver');

const hosts = (process.env.CASSANDRA_HOSTS || '').split(',').filter(Boolean);
const adminPassword = process.env.ADMIN_PASSWORD;

if (!hosts.length || !adminPassword) {
  console.error('缺少环境变量：CASSANDRA_HOSTS / CASSANDRA_PASSWORD / ADMIN_PASSWORD');
  process.exit(1);
}

const KEYSPACE = process.env.CASSANDRA_KEYSPACE || 'booksdemo';

const client = new cassandra.Client({
  contactPoints: hosts,
  port: parseInt(process.env.CASSANDRA_PORT || '9042', 10),
  localDataCenter: process.env.CASSANDRA_DC || 'datacenter1',
  authProvider: new cassandra.auth.PlainTextAuthProvider(
    process.env.CASSANDRA_USERNAME || 'root',
    process.env.CASSANDRA_PASSWORD
  ),
});

async function ensureTable(ddl) {
  try {
    await client.execute(ddl);
    console.log('[+] 表就绪:', ddl.match(/TABLE (IF NOT EXISTS )?(\w+)/)[2]);
  } catch (e) {
    throw e;
  }
}

async function main() {
  await client.execute(
    `CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE} WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3}`
  );
  console.log(`[+] keyspace 就绪: ${KEYSPACE}`);

  await ensureTable(`CREATE TABLE IF NOT EXISTS ${KEYSPACE}.books (
    isbn text PRIMARY KEY,
    title text,
    year int,
    author text,
    publisher text,
    rating int,
    pages int
  )`);
  await ensureTable(`CREATE TABLE IF NOT EXISTS ${KEYSPACE}.users (
    username text PRIMARY KEY,
    salt text,
    password_hash text,
    email text
  )`);

  // 默认用户 admin（已存在则跳过）
  const existing = await client.execute(
    `SELECT username FROM ${KEYSPACE}.users WHERE username = 'admin'`
  );
  if (existing.first()) {
    console.log('[=] 用户 admin 已存在，跳过');
  } else {
    const salt = crypto.randomBytes(16).toString('hex');
    const passwordHash = crypto.createHmac('sha256', salt).update(adminPassword).digest('hex');
    await client.execute(
      `INSERT INTO ${KEYSPACE}.users (username, salt, password_hash, email) VALUES (?, ?, ?, ?)`,
      ['admin', salt, passwordHash, 'admin@example.com'],
      { prepare: true }
    );
    console.log('[+] 默认用户已写入: admin');
  }

  await client.shutdown();
  console.log('[+] 初始化完成');
}

main().catch(e => {
  console.error('初始化失败:', e);
  process.exit(1);
});
