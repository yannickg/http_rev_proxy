-module(http_proxy_protocol).

%% public API
-export([start_link/4, init/4]).

start_link(ListenerPid, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport, Opts]),
	{ok, Pid}.

init(ListenerPid, Socket, Transport, Opts) ->
	lager:info("Options are: ~p", [Opts]),

	case proplists:get_value(http_proxy_tcp, Opts, undefined) of
		undefined ->
			lager:info ("closing socket", []),
			ok = Transport:close(Socket);
		CallbackPid ->
			lager:info ("listening socket", []),
			http_proxy_tcp:tcp_open(CallbackPid, Socket, Transport),
			ranch:accept_ack(ListenerPid),
			loop(Socket, Transport, CallbackPid)
	end.

loop(Socket, Transport, CallbackPid) ->
	lager:info ("http_proxy_protocol:loop", []),
	case Transport:recv(Socket, 0, 30000) of
		{ok, Data} ->
			lager:info ("received message - Data: ~p", [Data]),
			http_proxy_tcp:tcp_message(CallbackPid, Socket, Transport, Data),
			loop(Socket, Transport, CallbackPid);
		_ ->
			lager:info ("socket disconnected", []),
			http_proxy_tcp:tcp_close(CallbackPid, Socket, Transport)
	end.
