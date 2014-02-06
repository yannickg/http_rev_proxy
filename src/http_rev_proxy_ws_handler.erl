-module(http_rev_proxy_ws_handler).
-behaviour(cowboy_websocket_handler).

-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).

init({tcp, http}, _Req, _Opts) ->
   lager:info("~16w http_rev_proxy_ws_handler:init", [self()]),
	{upgrade, protocol, http_rev_proxy_websocket}.

websocket_init(_TransportName, Req, _Opts) ->
   {ok, Req, undefined_state}.

websocket_handle(_Data, Req, State) ->
   {ok, Req, State}.

websocket_info(_Info, Req, State) ->
	{ok, Req, State}.

websocket_terminate(_Reason, _Req, _State) ->
	ok.
