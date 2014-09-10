Promise = require 'bluebird'
redis = Promise.promisifyAll require "redis"

db =
  models: {}
  config: {}
  r: null
  Promise: Promise
  createId: require './createId'

  init: (cfg = {}, ns) ->
    cfg.host ?= '127.0.0.1'
    cfg.port ?= '6379'
    cfg.db ?= 0
    cfg.SEP ?= ':'
    cfg.prefix ?= ''

    @r ?= redis.createClient cfg.port, cfg.host
    @r.select cfg.db
    @config = cfg
    @ns = ns if ns?
    @r.on 'error', @onError

    @

  onError: (err) =>
    console.error "Redis Error", err

  addModel: (model) ->
    @models[model::constructor.name] = model

  addModels: (models) ->
    for model in models
      @models[model::constructor.name] = model

  afterSave: (model, changes, modelName) ->


db.Model = require('./Model')(db)

module.exports = db