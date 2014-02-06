%% Feel free to use, reuse and abuse the code in this file.

%% @doc Hello world handler.
-module(http_rev_proxy_handler).

-export([init/3]).
-export([handle/2]).
-export([terminate/3]).

init(_Type, Req, []) ->
   lager:info("~16w http_rev_proxy_handler:init", [self()]),
	{ok, Req, undefined_state}.

handle(Req, _) ->
   lager:info("~16w http_rev_proxy_handler:handle", [self()]),
   http_rev_proxy_connection:proxy_request(Req),
	{ok, Req, undefined_state}.

terminate(_Reason, _Req, _State) ->
   lager:info("~16w http_rev_proxy_handler:terminate", [self()]),
	ok.
