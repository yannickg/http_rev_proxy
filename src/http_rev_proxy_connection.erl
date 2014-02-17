%% Copyright (c) 2014, Yannick Guay <yannick.guay@gmail.com>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(http_rev_proxy_connection).

-export([proxy_request/1]).

-record(state, {
   socket_from = undefined :: inet:socket(),
   transport_from = undefined :: module(),
   socket_to = undefined :: inet:socket(),
   transport_to = undefined :: module()
}).

server_from_list([{Key, Value}|_], _Path) when Key =:= "/[...]" ->
   Value;
server_from_list([{Key, Value}|_], Path) when Key =:= Path ->
   Value;
server_from_list([{_, _}|Tail], Path) ->
   server_from_list(Tail, Path);
server_from_list([], _Path) ->
   undefined.

proxied_server(Req) ->
   {ok, List} = application:get_env(http_rev_proxy, proxied_servers),
   {Bin, _} = cowboy_req:path(Req),
   Path = binary_to_list(Bin),
   server_from_list(List, Path).

set_socket_options(true, #state{socket_from=Socket, transport_from=Transport}) ->
   Transport:setopts(Socket, [{active, once}]);
set_socket_options(false, _) ->
   ok.

proxy_request(Req) ->
   lager:info("~16w http_rev_proxy_connection:proxy_request", [self()]),

   {Host, Port} = proxied_server(Req),
   {ok, SocketTo} = gen_tcp:connect(Host, Port, [binary, {active, once}, {nodelay, true}, {reuseaddr, true}]),

   % Rewrite headers.
   Req2 = http_rev_proxy_request:new(Req),
   {Packet, Req3} = http_rev_proxy_request:build_packet(Req2),
   gen_tcp:send(SocketTo, Packet),

   [SocketFrom, TransportFrom] = cowboy_req:get([socket, transport], Req),
   State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=gen_tcp},
   set_socket_options(http_rev_proxy_request:socket_requires_options(Req3), State),
   socket_listener(State).

socket_listener(State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=TransportTo}) ->
   lager:info("~16w http_rev_proxy_handler:socket_listener", [self()]),
   receive
      {tcp, SocketTo, Data} ->
         inet:setopts(SocketTo, [{active, once}]),
         TransportFrom:send(SocketFrom, Data),
         socket_listener(State);
      {tcp_closed, SocketTo} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_closed", [self()]);
      {tcp_error, SocketTo, _Reason} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_error", [self()]);
      {tcp, SocketFrom, Data} ->
         inet:setopts(SocketFrom, [{active, once}]),
         TransportTo:send(SocketTo, Data),
         socket_listener(State);
      {tcp_closed, SocketFrom} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_closed", [self()]);
      {tcp_error, SocketFrom, _Reason} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_error", [self()])
   end.
