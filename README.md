trading-client
==============

A trading client for [a bitcoin futures exchange](www.icbit.se).

Trading algorithms can be implemented by subclassing **icbitClient.coffee** and overriding its methods.

Example
=======

**example_algo.coffee** contains an implementation of a VWAP reversion trading algorithm.

Enter an API key and symbols of the contracts to trade in **Config.coffee**.  Then:

```
./run.coffee
```
