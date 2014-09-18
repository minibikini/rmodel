validator = require 'validator'
inflection = require 'inflection'
typeOf = require 'typeof'
Promise = require 'bluebird'
isArray = Array.isArray

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

      Object.defineProperty @, '_orig',
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
                opts.get.call @, @_data[name]
              else
                @_data[name]

            set: (value) =>
              if opts.set?
                value = opts.set.call @, @_data[name], value

              return if @_isNew and not value?

              type = (opts.type or opts).toLowerCase()

              if value?
                value = switch type
                  when 'string' then validator.toString value
                  when 'number', 'float', 'int' then validator.toFloat value
                  when 'boolean' then validator.toBoolean value
                  else value

              if @_data[name] isnt value
                @_orig[name] ?= @_data[name] if @_data[name]?
                @_changes[name] = value

              @_data[name] = value

      # load data
      @[key] = val for key, val of data
      @applyDefaults() if isNew

    applyDefaults: ->
      _c = @constructor

      for key, opts of _c.schema when not @[key]? and opts.default?
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

    _save: ->
      _c = @constructor

      unless @[_c.primaryKey]
        return Promise.reject new Error "#{_c.name} - Primary key `#{_c.primaryKey}` is required"

      unless @isChanged()
        return Promise.resolve @

      toSave = {}
      toDelete = []
      tasks = []

      for key, val of @_changes
        if typeOf(val) in ['null', 'undefined']
          toDelete.push key
        else
          toSave[key] = val

      tasks.push db.r.hdelAsync [@getKey()].concat toDelete if toDelete.length
      tasks.push db.r.hmsetAsync @getKey(), toSave if Object.keys(toSave).length
      tasks.push @updateIndexes()

      Promise.all(tasks).then =>
        _changes = @_changes
        @_isNew = no
        @_changes = {}
        _c.afterSave @, _changes, _c.name
        @

    save: (cb) ->
      promise = @_save()
      promise.nodeify cb if cb?
      promise

    @afterSave: (model, changes, modelName) ->
      if @db.afterSave?
        @db.afterSave model, changes, modelName

    updateIndexes: ->
      _c = @constructor
      pfx = db.config.prefix
      SEP = db.config.SEP
      tasks = []

      # Adding ID to the model index
      if @_isNew
        idIndexKey = pfx + _c.name + "Ids"
        tasks.push db.r.saddAsync idIndexKey, @[_c.primaryKey]

      # Schema Indexes
      for name, opts of _c.schema when opts.index
        if @_orig[name] and @_orig[name] isnt ['']
          key = pfx + _c.name + 'Idx' + SEP + name + SEP + @_orig[name]
          tasks.push db.r.sremAsync key, @id

        if @_changes[name] and @_changes[name] not in ['']
          key = pfx + _c.name + 'Idx' + SEP + name + SEP + @_changes[name]
          tasks.push db.r.saddAsync key, @id

      # Associations Indexes
      if _c.relationships
        for name, opts of _c.relationships
          switch opts.type
            when 'belongsTo'
              if @_orig[opts.foreignKey] and @_orig[opts.foreignKey] not in ['']
                key = pfx + opts.model + SEP + @_orig[opts.foreignKey] + SEP + 'hasMany' + SEP  + _c.name
                tasks.push db.r.sremAsync key, @id

              if @_changes[opts.foreignKey] and @_changes[opts.foreignKey] not in ['']
                key = pfx + opts.model + SEP + @_changes[opts.foreignKey] + SEP + 'hasMany' + SEP  + _c.name
                tasks.push db.r.saddAsync key, @id

      Promise.all tasks

    @deserialize: (data) ->
      for key, opts of @schema when data[key]?
        type = (opts.type or opts).toLowerCase()
        data[key] = switch type
          when 'string' then validator.toString data[key]
          when 'number', 'float', 'int' then validator.toFloat data[key]
          when 'boolean' then validator.toBoolean data[key]
          else data[key]
      data

    @get: (id, cb) ->
      promise = if isArray id
        Promise.map id, (id) => @get id
      else
        db.r.hgetallAsync(@getKey id).then (reply) =>
          return unless reply
          model = new @ {}, no
          model._data = @deserialize reply
          model

      promise.nodeify cb if cb?
      promise

    @getBy: (idx, val, opts = {}) ->
      modelName = @::constructor.name
      pfx = db.config.prefix
      SEP = db.config.SEP

      key = pfx + modelName + 'Idx' + SEP + idx + SEP + val

      db.r.smembersAsync(key).then (ids) =>
        @getWith ids, opts.with

    @getWith: (id, rels = [], cb) ->
      rels = [rels] unless isArray rels
      rels = Promise.resolve rels

      promise = @get(id).then (model) =>
        return unless model

        loadRels = (model) ->
          rels.each((r) -> model.get r).then -> model

        if isArray model
          Promise.map model, loadRels
        else
          loadRels model

      promise.nodeify cb if cb?
      promise

    get: (rel, cb) ->
      c = @constructor
      rel = name: rel unless rel.name?

      hasRelation = (c.relationships and relation = c.relationships[rel.name]) and (relation.type and relation.model and db.models[relation.model])

      promise = if hasRelation
        switch c.relationships[rel.name].type
          when 'hasMany' then @_getHasMany rel
          when 'belongsTo' then @_getBelongsTo rel
          else Promise.resolve()
      else
        Promise.resolve()

      promise.nodeify cb if cb?
      promise

    _getHasMany: (query) ->
      relation = @constructor.relationships[query.name]
      key = @getKey() + db.config.SEP + 'hasMany' + db.config.SEP + relation.model

      db.r.smembersAsync(key).then (ids) =>
        db.models[relation.model]
          .getWith ids, query.with or relation.with
          .then (records) => @[query.name] = records

    _getBelongsTo: (query) ->
      relation = @constructor.relationships[query.name]

      db.models[relation.model]
        .getWith @[relation.foreignKey], query.with or relation.with
        .then (model) => @[query.name] = model

    # deletes hash by ID from db
    @del: (id, cb) ->
      promise = @get(id).then (model) -> model.del()
      promise.nodeify cb if cb?
      promise

    # alias for @del
    @remove: (id, cb) -> @del id, cb

    # deletes hash from db
    del: (cb) ->
      _c = @constructor
      pfx = db.config.prefix
      SEP = db.config.SEP

      tasks = []
      id = @[_c.primaryKey]

      idIndexKey = pfx + _c.name + "Ids"
      tasks.push db.r.sremAsync idIndexKey, id

      if _c.relationships
        for name, opts of _c.relationships
          switch opts.type
            when 'belongsTo'
              if foreignId = @[opts.foreignKey]
                key = pfx + opts.model + SEP + foreignId + SEP + 'hasMany' + SEP  + _c.name
                tasks.push db.r.sremAsync key, id

              if foreignId = @_orig[opts.foreignKey]
                key = pfx + opts.model + SEP + foreignId + SEP + 'hasMany' + SEP  + _c.name
                tasks.push db.r.sremAsync key, id

      tasks.push db.r.delAsync @getKey()

      promise = Promise.all tasks
      promise.nodeify cb if cb?
      promise

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

    @update: (id, data, cb) ->
      promise = @get(id).then (model) ->
        model[key] = val for key, val of data
        model.save()

      promise.nodeify cb if cb?
      promise

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
      promise = @db.r.scardAsync key
      promise.nodeify cb if cb?
      promise
