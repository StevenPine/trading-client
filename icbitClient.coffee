###
A base class for trading algorithms
###

io       = require 'socket.io-client'
CryptoJS = require 'crypto-js'

logger = require './logs/logger'

class IcbitClient
    ###
    User data and methods + a dictionary of the Contract class.
    ###

    constructor: (@config)->
        @conn      = undefined

        @contracts         = {}
        @contracts[ticker] = new Contract for ticker in @config.tickers

        @btc               = undefined
        @margin            = undefined

    # "virtual" methods

    on_user_balance : (user_balance) =>
        null

    on_user_order :(user_order) =>
        null

    on_order_book : (order_book) =>
        null

    on_ticker : (ticker) =>
        null

    on_trades : (trades) =>
        null

    on_user_trades : (trades) =>
        null
    
    # global updates  not contract specific 

    update_btc_margin : (position) =>
        @btc    = position.qty/1e8
        @margin = position.margin

    update_chat : (message) =>
        null
        
    update_status : (status) =>
        null

    # methods to handle orders

    place_order : (type,price,quantity,ticker,token) =>
        specifics = @contracts[ticker].specifics
        price_min = specifics.price_min * specifics.tick_size
        price_max = specifics.price_max * specifics.tick_size

        if price_min < price < price_max
            order = 
                "op":"create_order"
                "order":
                    "market": 1 #market
                    "ticker": ticker
                    "buy"   : type
                    "price" : parseInt(price/@contracts[ticker].specifics.tick_size)
                    "qty"   : quantity
                    "token" : token

            @conn.emit 'message', order

    cancel_order : (oid) =>
        cancel =
            "op"    :"cancel_order"
            "order" :
                "oid"    : oid
                "market" : 1

        @conn.emit 'message', cancel

    cancel_all : =>
        open_order_oids = []
        for ticker in @config.tickers
            open_order_oids.push oid for oid,order of @contracts[ticker].my_orders when (order.status is 0 or order.status is 1) 

        for i,oid of open_order_oids
            setTimeout @cancel_order, i*1000, oid 

    cancel_ticker : (ticker,type) =>
        open_order_oids = []
        open_order_oids.push oid for oid,order of @contracts[ticker].my_orders when (order.status is 0 or order.status is 1) and order.type is type 

        for i,oid of open_order_oids
            setTimeout @cancel_order, i*1000, oid 

    
    variation_margin : (price_open,price_close,number_of_contracts,fee,lot_size) =>
        number_of_contracts = if typeof(number_of_contracts) is "undefined" then 1 else number_of_contracts
        fee                 = if typeof(fee) is "undefined" then 0.0001 else fee
        lot_size            = if typeof(lotSize) is "undefined" then 10 else lotSize
        
        return -1 * ( 1/price_close - 1/price_open)* lot_size * number_of_contracts - 2*fee

    # methods to handle and configure connection

    start_connection : =>
        nonce     = Math.round Date.now()/1000
        userid    = @config.config.userid
        key       = @config.config.key
        secret    = @config.config.secret
        signature = CryptoJS.HmacSHA256(nonce + userid + key, secret).toString(CryptoJS.enc.Hex).toUpperCase()

        @conn      = io.connect('https://api.icbit.se:443/icbit?key=' + key + '&signature=' + signature + '&nonce=' + nonce)

        @conn.on 'connect', ( setTimeout  @subscribe, 2500)
        @conn.on 'message', @parse_message

    subscribe : =>
        for ticker of @contracts
            @conn.emit 'message', { op: 'subscribe', channel: 'orderbook_' + ticker}
            @conn.emit 'message', { op: 'subscribe', channel: 'ticker_' + ticker}
            @conn.emit 'message', { op: 'subscribe', channel: 'trades_' + ticker}
            @conn.emit 'message', { op: 'subscribe', channel: 'user_trades'}

        @conn.emit 'message', { op: 'get', type: 'user_order'}
        @conn.emit 'message', { op: 'get', type: 'user_balance'}
        @conn.emit 'message', { op: 'get', type: 'user_trades'}

        logger.info 'subscribed'

    parse_message : (message) =>
        if message.channel is 'dictionary'
            @contracts[item.ticker].update_specifics(item.r,item.fee,item.price_min, item.price_max, item.im_buy, item.im_sell,item.expiry) for item in message.instruments
        else if message.channel is 'user_balance'
            positions = message.user_balance
            
            for position in positions
                if position.ticker of @contracts
                    @contracts[position.ticker].update_position( position.price
                                                                 position.qty
                                                                 position.vm
                                                                 position.mm) 
                else if position.ticker is 'BTC'
                    @update_btc_margin(position)

            @on_user_balance message.user_balance
        else if message.channel is 'user_order'
            orders = message.user_order
            @contracts[order.ticker].update_my_orders(order) for order in orders
            
            @on_user_order message.user_order
        else if message.channel.split('_')[0] is 'orderbook'
            order_book = message.orderbook
            @contracts[order_book.s].order_book = 
                buy  :   order_book.buy
                sell :   order_book.sell

            @on_order_book message.orderbook
        else if message.channel.split('_')[0] is 'ticker'
            ticker = message.ticker
            @contracts[ticker.ticker].update_ticker(ticker)

            @on_ticker message.ticker
        else if message.channel.split('_')[0] is 'trades'
            @contracts[message.trade.ticker].update_trades( message.trade )

            @on_trades message.trade
        else if message.channel is 'user_trades'
            trades = message.user_trades
            @contracts[trade.ticker].update_my_trades(trade) for trade in trades when trade.ticker of @contracts

            @on_user_trades message.user_trades
        else if message.channel is 'chat_general'
            @update_chat message
        else if message.channel is 'status'
            @update_status message.status
        else
            logger.info "uncaught message: ", message

        logger.info message

class Contract
    ###
    All of the information and methods for a given contract.
    ###

    constructor: ->
        @specifics = 
            tick_size : undefined
            fee       : undefined
            price_min : undefined
            price_max : undefined
            im_buy    : undefined
            im_sell   : undefined
            expiry    : undefined

        @order_book = 
            buy       : []
            sell      : []

        @my_orders  = {}

        @position = 
            price   : undefined
            quantity: undefined
            pl      : undefined
            margin  : undefined

        @ticker =
            ts       : undefined
            last     : undefined
            last_qty : undefined
            vwap60   : undefined
            oi       : undefined
            volume   : undefined
            bid      : undefined
            ask      : undefined
            bid_qty  : undefined
            ask_qty  : undefined

        @trades    = []
        @my_trades = []

    # setters

    update_specifics: (tick_size, fee,price_min,price_max,im_buy,im_sell,expiry) =>
        @specifics = 
            tick_size : tick_size
            fee       : fee
            price_min : price_min
            price_max : price_max 
            im_buy    : im_buy    
            im_sell   : im_sell   
            expiry    : expiry    
        
    update_position: (price, quantity, pl, margin) =>
        @position = 
            price     : price
            quantity  : quantity
            pl        : pl
            margin    : margin

    update_my_orders: (order) =>
        @my_orders[order.oid] = 
            price    :order.price
            quantity :order.qty
            type     :order.type
            date     :order.date
            fills    :order.fills
            token    :order.token
            status   :order.status

    update_ticker: (ticker) =>
        @ticker =
            ts       : ticker.ts
            last     : ticker.last
            last_qty : ticker.last_qty
            vwap60   : ticker.vwap60
            oi       : ticker.oi
            volume   : ticker.volume
            bid      : ticker.bid
            ask      : ticker.ask
            bid_qty  : ticker.bid_qty
            ask_qty  : ticker.ask_qty
    
    update_trades : (trade) =>
        @trades.push trade

    update_my_trades : (trade) =>
        @my_trades.push trade

    #getters

    get_my_open_orders: (type) =>
        my_open_orders  =  []
        my_open_orders.push order for oid,order of @my_orders when order.status is 0 or order.status is 1

        return my_open_orders
    
    get_not_my_order_book:(type) =>
        not_my_order_book = 
            buy  : []
            sell : []
    
        my_open_orders = {}
        my_open_orders[o.price] = o.quantity for o in @get_my_open_orders() when o.type is type

        for order in @order_book[if type is 0 then 'buy' else 'sell']
            o = 
                p : order.p
                q : order.q - (if order.p of my_open_orders then my_open_orders[order.p] else 0)

            not_my_order_book[if type is 0 then 'buy' else 'sell'].push(o)

        return not_my_order_book[if type is 0 then 'buy' else 'sell']

module.exports = IcbitClient
