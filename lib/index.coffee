redis = require 'redis'
typeOf = require 'typeof'

db =
  models: {}
  config: {}
  r: null
  createId: require './createId'

Model = require('./Model')(db)

module.exports =
  r: db.r
  models: db.models
  Model: Model

  init: (cfg = {}, ns) ->
    cfg.host ?= '127.0.0.1'
    cfg.port ?= '6379'
    cfg.db ?= 0
    cfg.SEP ?= ':'
    cfg.prefix ?= ''

    @r = db.r = redis.createClient cfg.port, cfg.host
    db.r.select cfg.db
    db.config = cfg
    db.ns = ns if ns?
    @r.on 'error', @onError

    @

  onError: (err) =>
    console.error "Redis Error", err

  addModel: (model) ->
    db.models[model::constructor.name] = model

  addModels: (models) ->
    for model in models
      db.models[model::constructor.name] = model

  createId: db.createId