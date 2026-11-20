// books-create：新增图书（POST /books，需 JWT 鉴权）
// 数据访问：GeminiDB Cassandra（CQL），连接信息经环境变量传递
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

exports.handler = async (event, context) => {
  try {
    const book = JSON.parse(event.body);
    const { isbn, title, year, author, publisher, rating, pages } = book;

    await getClient().execute(
      'INSERT INTO books (isbn, title, year, author, publisher, rating, pages) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [isbn, title, parseInt(year, 10), author, publisher, parseInt(rating, 10), parseInt(pages, 10)],
      { prepare: true }
    );

    return {
      statusCode: 201,
      headers: { 'Content-Type': 'application/json' },
      body: '',
    };
  } catch (e) {
    console.error('create book error:', e);
    return { statusCode: 500, headers: {}, body: '' };
  }
};
