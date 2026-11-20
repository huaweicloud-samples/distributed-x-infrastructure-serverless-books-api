// books-get-all：查询全部图书（GET /books，公开）
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
    const rs = await getClient().execute('SELECT isbn, title, year, author, publisher, rating, pages FROM books');

    const books = rs.rows.map(row => ({
      isbn: row.isbn,
      title: row.title,
      year: row.year,
      author: row.author,
      publisher: row.publisher,
      rating: row.rating,
      pages: row.pages,
    }));

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(books),
    };
  } catch (e) {
    console.error('get all books error:', e);
    return { statusCode: 500, headers: {}, body: '' };
  }
};
