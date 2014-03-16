#! /usr/bin/coffee

Config = require './config'
Algo   = require './example_algo'

sess = new Algo(Config)
sess.start_connection()
