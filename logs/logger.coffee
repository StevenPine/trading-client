###
Configuration for the logger
###

winston  = require 'winston'

logger = new winston.Logger { 
                                      transports: [
                                                      new winston.transports.File {name:'data#json',filename:'logs/data.json.log',timestamp:true}
                                                      new winston.transports.File {name:'data',filename:'logs/data.log',json:false,timestamp:true}
                                                  ]
                                  }

module.exports = logger
