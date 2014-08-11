hostname = require('os').hostname()
crypto = require('crypto')

hash = (str) -> crypto.createHash('md5').update(str).digest 'hex'

module.exports = ->
  strings = (key for key in arguments)
  strings.push Date.now(), hostname, process.pid, Math.random()

  hash strings.join('-')