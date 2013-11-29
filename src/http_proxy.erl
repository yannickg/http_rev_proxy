-module(http_proxy).

%% API.
-export([start/0]).

%% API.

start() ->
	lager:start(),
	ok = application:start(ranch),
	ok = application:start(http_proxy).
