###
A subclass of icbitClient.coffee that places an order when the bid or the ask deviates sufficiently far from the 60 minute VWAP.
###

logger = require './logs/logger'
IcbitClient = require './icbitClient'

class Algo extends IcbitClient
   ###
   update_tickers from the parent class is modified to check for and trade on desirable conditions.
   ###

   on_ticker: (ticker) =>
        ###
        check for correct condtions and place order is desirable. 
        ###


        symbol   = ticker.ticker

        tick     = @contracts[symbol].specifics.tick_size
        fee      = @contracts[symbol].specifics.fee / 1e8
        quantity = 1
        lot_size = 10

        vwap60   = ticker.vwap60 * tick
        last     = ticker.last   * tick
        bid      = ticker.bid    * tick
        ask      = ticker.ask    * tick
        
        logger.info "Ticker: #{symbol}  - bid: #{bid}   - ask: #{ask}   - vwap60: #{vwap60} -   last: #{last}"

        # compare profit to fees
        under_vwap = @variation_margin( ask, vwap60, quantity, fee)
        over_vwap  = @variation_margin( vwap60, bid, quantity, fee)

        if over_vwap > 0
            logger.info "Bid is above VWAP by #{over_vwap}. Selling."
            @place_order(0,bid,1,ticker,0)
        else if under_vwap >0
            logger.info "Ask is below VWAP by #{under_vwap}. Buying."
            @place_order(1,ask,1,ticker,0) 

    on_user_order: (order) =>
        ###
        clean up stray or missed orders
        ###

        ticker = order[0].ticker

        @cancel_ticker(ticker,1)
        @cancel_ticker(ticker,0)

module.exports = Algo
