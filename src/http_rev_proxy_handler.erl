%% Feel free to use, reuse and abuse the code in this file.

%% @doc Hello world handler.
-module(http_rev_proxy_handler).

-export([init/3]).
-export([handle/2]).
-export([terminate/3]).

-record(state, {
   socket_from = undefined :: inet:socket(),
   transport_from = undefined :: module(),
   socket_to = undefined :: inet:socket(),
   transport_to = undefined :: module()
}).

init(_Type, Req, []) ->
   lager:info("~16w http_rev_proxy_handler:init", [self()]),
	{ok, Req, undefined_state}.

handle(Req, _) ->
   lager:info("~16w http_rev_proxy_handler:handle", [self()]),
   [SocketFrom, TransportFrom] = cowboy_req:get([socket, transport], Req),
   {ok, TransportTo, SocketTo} = http_rev_proxy_connection:received_request(Req),
   State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=TransportTo},
   socket_listener(State),
	{ok, Req, State}.

terminate(_Reason, _Req, _State) ->
   lager:info("~16w http_rev_proxy_handler:terminate", [self()]),
	ok.

socket_listener(State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=TransportTo}) ->
   lager:info("~16w http_rev_proxy_handler:socket_listener", [self()]),
   receive
      {tcp, SocketTo, Data} ->
         inet:setopts(SocketTo, [{active, once}]),
         TransportFrom:send(SocketFrom, Data),
         socket_listener(State);
      {tcp_closed, _SocketTo} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_closed", [self()]),
         ok;
      {tcp_error, _SocketTo, _Reason} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_error", [self()]),
         ok;
      {tcp, SocketFrom, Data} ->
         inet:setopts(SocketFrom, [{active, once}]),
         TransportTo:send(SocketTo, Data),
         socket_listener(State);
      {tcp_closed, _SocketFrom} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_closed", [self()]),
         ok;
      {tcp_error, _SocketFrom, _Reason} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_error", [self()]),
         ok
   end.
