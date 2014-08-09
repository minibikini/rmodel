RedisModel = (require '../../lib').Model

module.exports = class Post extends RedisModel
  @schema:
    id: 'string'
    title: 'string'
    body: 'string'
