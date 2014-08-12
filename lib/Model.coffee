validator = require 'validator'
inflection = require 'inflection'
typeOf = require 'typeof'
async = require 'async'

module.exports = (db) ->
  class RedisModel
    @db: db
    @primaryKey: "id"
    constructor: (data = {}, isNew = yes) ->
      Object.defineProperty @, '_isNew',
        value: isNew
        enumerable: no
        writable: yes

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
      _c = @constructor

      for key, opts of _c.schema when opts.default?
        @[key] = if typeOf(opts.default) is 'function'
          opts.default.call @, key
        else
          opts.default

      if _c.schema.id? and not @id? and db.createId?
        @id = db.createId _c.name

    @getKey: (id) ->
      db.config.prefix + @::constructor.name + db.config.SEP + id

    getKey: ->
      @constructor.getKey @[@constructor.primaryKey]

    save: (cb) ->
      _c = @constructor
      unless  @[_c.primaryKey]
        return cb new Error "Primary key is required"

      db.r.hmset @getKey(), @_changes, (err, reply) =>
        return cb err, reply if err?

        if not @_isNew
          @_changes = {}
          cb err, @
        else
          @updateIndexes (err) =>
            return cb err, reply if err?
            @_changes = {}
            @_isNew = no
            cb err, @

    updateIndexes: (cb) ->
      _c = @constructor
      tasks = []

      # Adding ID to the model index
      tasks.push (done) =>
        idIndexKey = db.config.prefix + _c.name + "Ids"
        db.r.sadd idIndexKey, @[_c.primaryKey], done

      if _c.relationships
        for name, opts of _c.relationships
          do (name, opts) =>
            switch opts.type
              when 'belongsTo'
                if @[opts.foreignKey]?
                  tasks.push (done) =>
                    key = db.config.prefix + opts.model + db.config.SEP + @[opts.foreignKey] + db.config.SEP + 'hasMany' + db.config.SEP  + _c.name
                    db.r.sadd key, @id, done

      async.parallel tasks, cb


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
          model = new @ {}, no
          model._data = @deserialize reply
          cb err, model

    @getWith: (id, rels, cb) ->
      rels = [] unless rels?
      rels = [rels] unless typeOf(rels) is 'array'

      @get id, (err, model) ->
        return cb err, model if err? or not model?

        loadRels = (model, cb) ->
          async.each rels, ((r, fn) -> model.get r, fn), (err) ->
            cb err, model

        if typeOf(model) is 'array'
          async.map model, loadRels, cb
        else
          loadRels model, cb

    get: (rel, cb) ->
      c = @constructor
      # return cb unless rel?

      unless rel.name?
        rel = name: rel

      unless c.relationships and relation = c.relationships[rel.name]
        return cb null, null

      unless relation.type and relation.model and db.models[relation.model]
        return cb null, null

      switch c.relationships[rel.name].type
        when 'hasMany' then @_getHasMany rel, cb
        when 'belongsTo' then @_getBelongsTo rel, cb
        else cb null, null

    _getHasMany: (rel, cb) ->
      relation = @constructor.relationships[rel.name]
      key = @getKey() + db.config.SEP + 'hasMany' + db.config.SEP + relation.model

      db.r.smembers key, (err, ids) =>
        db.models[relation.model].getWith ids, rel.with, (err, records) =>
          @[rel.name] = records
          cb err, records

    _getBelongsTo: (rel, cb) ->
      relation = @constructor.relationships[rel.name]
      db.models[relation.model].getWith @[relation.foreignKey], rel.with, (err, model) =>
        return cb err if err?
        @[rel.name] = model
        cb null, model

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
      opts.foreignKey ?= inflection.camelize @::constructor.name + '_id', true
      @relationships[name] = opts

    @belongsTo: (name, opts = {}) ->
      @relationships ?= {}
      opts.model ?= inflection.classify name
      opts.type ?= 'belongsTo'
      opts.name ?= name
      opts.foreignKey ?= name + 'Id'
      @relationships[name] = opts

    @count: (cb) ->
      key = @db.config.prefix + @::constructor.name + 'Ids'
      @db.r.scard key, cb