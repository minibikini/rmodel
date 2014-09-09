gulp = require 'gulp'
mocha = require 'gulp-mocha'
gulp.task 'default', ['test']
pe = new (require('pretty-error'))

gulp.task 'test', ->
  gulp.src './test/*.test.coffee'
    .pipe mocha
      reporter: 'spec'
      bail: yes
    .on 'error', (err) ->
      console.log pe.render err
      @emit 'end'

gulp.task 'watch', ->
  gulp.watch ['./examples/**/*.coffee', './test/**/*.coffee', './lib/**/*.coffee'], ['test']
