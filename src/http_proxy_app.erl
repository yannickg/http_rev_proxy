-module(http_proxy_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	{ok, _} = ranch:start_listener(http_proxy, 1,
		ranch_tcp, [{port, 5555}], http_proxy_protocol, []),
	ranch:set_protocol_options(http_proxy, [{foo, "bar"}]),
    http_proxy_sup:start_link().

stop(_State) ->
    ok.
