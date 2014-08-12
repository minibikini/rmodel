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
    role:
      type: 'string'
      default: 'guest'

    likes:
      type: 'string'
      default: (propName) -> 'apples'

  @hasMany 'posts'


  fullName: ->
    @firstName + ' ' + @lastName