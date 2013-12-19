-module(http_proxy_protocol).

%% public API
-export([start_link/4, init/4]).

start_link(ListenerPid, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport, Opts]),
	{ok, Pid}.

init(ListenerPid, Socket, Transport, Opts) ->

	case proplists:get_value(http_proxy_tcp, Opts, undefined) of
		undefined ->
			ok = Transport:close(Socket);
		CallbackPid ->
			http_proxy_tcp:tcp_open(CallbackPid, Socket, Transport),
			ranch:accept_ack(ListenerPid),
			loop(Socket, Transport, CallbackPid)
	end.

loop(Socket, Transport, CallbackPid) ->
	case Transport:recv(Socket, 0, 30000) of
		{ok, Data} ->
			http_proxy_tcp:tcp_message(CallbackPid, Socket, Transport, Data),
			loop(Socket, Transport, CallbackPid);
		_ ->
			http_proxy_tcp:tcp_close(CallbackPid, Socket, Transport)
	end.
