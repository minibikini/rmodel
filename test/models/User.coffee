RedisModel = (require '../../lib').Model

module.exports = class User extends RedisModel
  # @primaryKey: 'username'

  @schema:
    id: 'string'
    username: 'string'
    email: 'string'
    firstName: 'string'
    lastName: 'string'
    age: 'number'
    isAdmin: 'boolean'

  fullName: ->
    @firstName + ' ' + @lastName