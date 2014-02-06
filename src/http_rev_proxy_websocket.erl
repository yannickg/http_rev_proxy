%% Copyright (c) 2011-2013, Yannick Guay <yannick.guay@gmail.com>
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

-module(http_rev_proxy_websocket).
-behaviour(cowboy_sub_protocol).

%% Ignore the deprecation warning for crypto:sha/1.
%% @todo Remove when we support only R16B+.
-compile(nowarn_deprecated_function).

%% API.
-export([upgrade/4]).

-record(state, {
   socket_from = undefined :: inet:socket(),
   transport_from = undefined :: module(),
   socket_to = undefined :: inet:socket(),
   transport_to = undefined :: module()
}).

upgrade(Req, Env, Handler, _HandlerOpts) ->
   lager:info("~16w http_rev_proxy_ws_handler:upgrade", [self()]),
	{_, Ref} = lists:keyfind(listener, 1, Env),
	ranch:remove_connection(Ref),

   [SocketFrom, TransportFrom] = cowboy_req:get([socket, transport], Req),
   TransportFrom:setopts(SocketFrom, [{active, once}]),
   {ok, TransportTo, SocketTo} = http_rev_proxy_connection:received_request(Req),
   State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=TransportTo},
   socket_listener(State).


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
