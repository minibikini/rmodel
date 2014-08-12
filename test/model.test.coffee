should = require('chai').should()
faker = require 'faker'
rmodel = require("../lib")

rmodel.init db: 1, prefix: "test:"

User = require './models/User'

getFakeUserData = ->
  id: faker.random.number([10000000000,90000000000])
  firstName: faker.Name.firstName()
  lastName: faker.Name.lastName()
  username: faker.Internet.userName()
  email: faker.Internet.email()
  age: faker.random.number([1,100])
  isAdmin: no

describe 'RedisModel', ->
  before (done) ->
    rmodel.r.flushall done

  # after (done) ->
  #   rmodel.r.flushall done

  describe 'Model Instance', ->
    user = null

    it 'should save new model to db', (done) ->
      user = new User getFakeUserData()
      user.isChanged().should.be.true
      user.save (err) ->
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
