redis = require 'redis'

db =
  models: {}
  config: {}
  r: null

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

  addModel: (model) ->
    db.models[model::constructor.name] = model