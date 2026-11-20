// apig-authorizer：APIG 自定义鉴权器（FRONTEND）
// 校验 Authorization: Bearer <JWT>；成功返回 principal_id + context，失败抛异常拒绝
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

exports.handler = async (event, context) => {
  const headers = event.headers || {};
  const authHeader = headers.Authorization || headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    console.log('authorized principal:', decoded.sub);
    return {
      principal_id: decoded.sub,
      context: {
        email: decoded.email,
        scope: decoded.scope,
      },
    };
  } catch (e) {
    console.error('authorize failed:', e.message);
    throw new Error('Unauthorized');
  }
};
