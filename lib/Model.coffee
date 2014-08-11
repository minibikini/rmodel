validator = require 'validator'
inflection = require 'inflection'
typeOf = require 'typeof'
async = require 'async'

module.exports = (db) ->
  class RedisModel
    @db: db
    @primaryKey: "id"
    constructor: (data = {}) ->
      Object.defineProperty @, 'prepend',
        value: @constructor.name + db.config.SEP
        enumerable: no
        writable: yes

      Object.defineProperty @, '_changes',
        value: {}
        enumerable: no
        writable: yes

      Object.defineProperty @, '_data',
        value: {}
        enumerable: no
        writable: yes

      # set up getters/setters
      for name, opts of @constructor.schema
        do (name, opts) =>
          Object.defineProperty @, name,
            enumerable: yes
            get: =>
              if opts.get?
                opts.get.apply @, @_data[name]
              else
                @_data[name]

            set: (value) =>
              if opts.set?
                value = opts.set.apply @, value

              if @_data[name] isnt value
                @_changes[name] = value

              @_data[name] = value

      # load data
      @[key] = val for key, val of data
      @applyDefaults()

    applyDefaults: ->
      for key, opts of @constructor.schema when opts.default?
        @[key] = if typeOf(opts.default) is 'function'
          opts.default.call @, key
        else
          opts.default


    @getKey: (id) ->
      db.config.prefix + @::constructor.name + db.config.SEP + id

    getKey: ->
      @constructor.getKey @[@constructor.primaryKey]

    save: (cb) ->
      unless  @[@constructor.primaryKey]
        return cb new Error "Primary key is required"

      db.r.hmset @getKey(), @_changes, (err, reply) =>
        return cb err, reply if err?
        @_changes = {}
        cb err, reply

    @deserialize: (data) ->
      for key, opts of @schema
        type = (opts.type or opts).toLowerCase()
        data[key] = switch type
          when 'string' then validator.toString data[key]
          when 'number', 'float', 'int' then validator.toFloat data[key]
          when 'boolean' then validator.toBoolean data[key]
          else data[key]
      data

    @get: (id, cb) ->
      if typeOf(id) is 'array'
        async.map id, ((el, done) => @get el, done), cb
      else
        db.r.hgetall @getKey(id), (err, reply) =>
          return cb err, reply if err? or not reply?
          model = new @
          model._data = @deserialize reply
          cb err, model

    @getWith: (id, rels, cb) ->
      rels = [rels] unless typeOf(rels) is 'array'
      @get id, (err, model) ->
        return cb err, model if err? or not model?
        async.each rels, ((r, fn) -> model.get r, fn), (err) ->
          cb err, model

    get: (rel, cb) ->
      c = @constructor

      unless rel.name?
        rel = name: rel

      unless c.relationships and relation = c.relationships[rel.name]
        return cb null, null

      unless relation.type and relation.model and db.models[relation.model]
        return cb null, null

      switch c.relationships[rel.name].type
        when 'hasMany' then @_getHasMany rel, cb
        else cb null, null

    _getHasMany: (rel, cb) ->
      relation = @constructor.relationships[rel.name]
      key = @getKey() + db.config.SEP + 'hasMany' + db.config.SEP + relation.model

      db.r.smembers key, (err, ids) =>
        db.models[relation.model].get ids, (err, records) =>
          @[rel.name] = records
          cb err, records

    # deletes hash by ID from db
    @del: (id, cb) -> db.r.del @getKey(id), cb

    # alias for @del
    @remove: (id, cb) ->

    # deletes hash from db
    del: (cb) -> db.r.del @getKey(), cb

    # alias for del
    remove: (cb) -> @del cb

    isChanged: (prop) ->
      if prop
        @_changes.hasOwnProperty prop
      else
        !!Object.keys(@_changes).length

    # Instantiate a new instance of the object and save.
    @create: (data, cb) ->
      (new @ data).save cb

    toObject: -> @_data

    @hasMany: (name, opts = {}) ->
      @relationships ?= {}
      opts.model ?= inflection.classify name
      opts.type ?= 'hasMany'
      opts.name ?= name
      @relationships[name] = opts

