RedisModel = (require '../../lib').Model

module.exports = class Comment extends RedisModel
  @schema:
    id: 'string'
    body: 'string'
    userId: 'string'
    postId: 'string'

  @belongsTo 'user'
  @belongsTo 'post'