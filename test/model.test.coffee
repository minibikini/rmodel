should = require('chai').should()
faker = require 'faker'
rmodel = require("../lib")
async = require 'async'

rmodel.init db: 15, prefix: "test:"

User = require './models/User'
Post = require './models/Post'

rmodel.addModels [User, Post, Comment]

getFakeUserData = ->
  firstName: faker.Name.firstName()
  lastName: faker.Name.lastName()
  username: faker.Internet.userName()
  email: faker.Internet.email()
  age: faker.random.number([1,100])
  isAdmin: no

describe 'RedisModel', ->
  before (done) ->
    rmodel.r.flushall done

  after (done) ->
    rmodel.r.flushall done

  describe 'Model Instance', ->
    user = null

    it 'should save new model to db', (done) ->
      user = new User getFakeUserData()
      user.isChanged().should.be.true
      user._isNew.should.be.true
      user.save (err) ->
        user._isNew.should.be.false
        should.not.exist err
        user.isChanged().should.be.false
        done()

    it 'should get a record from db', (done) ->
      user = new User getFakeUserData()
      user.save (err) ->
        should.not.exist err
        User.get user.id, (err, record) ->
          should.not.exist err
          should.exist record
          record.should.have.property 'id'
          done()

    it 'should delete a model from db', (done) ->
      user2 = new User getFakeUserData()
      user2.save (err) ->
        should.not.exist err
        user2.remove (err) ->
          should.not.exist err
          done()

  describe 'Defaults', ->
    it 'should have a property with a default value', ->
      user = new User getFakeUserData()
      should.exist user.role
      user.role.should.equal 'guest'

    it 'should have a property with a default defined by a function', ->
      user = new User getFakeUserData()
      should.exist user.likes
      user.likes.should.equal 'apples'

    it 'should create an id', ->
      user = new User
      should.exist user.id
      user.id.should.lengthOf 32

  describe 'Model Class', ->
    it '.count() should return a number of records', (done) ->
      User.count (err, count) ->
        should.not.exist err
        count.should.be.a 'number'
        done()

  describe 'Relations', ->
    user = null

    before (done) ->
      user = new User getFakeUserData()
      user.save ->
        createPost = (n, cb) ->
          post = new Post
          post.userId = user.id
          post.title = 'test'
          post.body = 'test'
          post.save cb

        async.times 10, createPost, done

    describe 'belongsTo', ->
      it 'should load belongsTo with .get(relName)', (done) ->
        post = new Post
        post.userId = user.id
        post.get 'user', (err, user2) ->
          should.not.exist err
          should.exist user2
          done()

      it 'should load hasMany with .get(relName)', (done) ->
        user.get 'posts', (err, posts) ->
          should.not.exist err
          posts.should.be.an 'array'
          posts.should.be.lengthOf 10
          done()