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

-type close_code() :: 1000..4999.
-export_type([close_code/0]).

-type frame() :: close | ping | pong
	| {text | binary | close | ping | pong, iodata()}
	| {close, close_code(), iodata()}.
-export_type([frame/0]).

-type opcode() :: 0 | 1 | 2 | 8 | 9 | 10.
-type mask_key() :: 0..16#ffffffff.
-type frag_state() :: undefined
   | {nofin, opcode(), binary()} | {fin, opcode(), binary()}.
-type rsv() :: << _:3 >>.

-record(state, {
	env :: cowboy_middleware:env(),
	socket = undefined :: inet:socket(),
	transport = undefined :: module(),
	handler :: module(),
	key = undefined :: undefined | binary(),
	timeout = infinity :: timeout(),
	timeout_ref = undefined :: undefined | reference(),
	messages = undefined :: undefined | {atom(), atom(), atom()},
	hibernate = false :: boolean(),
	frag_state = undefined :: frag_state(),
	utf8_state = <<>> :: binary(),
	deflate_frame = false :: boolean(),
	inflate_state :: undefined | port(),
	deflate_state :: undefined | port()
}).

upgrade(Req, Env, Handler, HandlerOpts) ->
	{_, Ref} = lists:keyfind(listener, 1, Env),
	ranch:remove_connection(Ref),
	[Socket, Transport] = cowboy_req:get([socket, transport], Req),
	State = #state{env=Env, socket=Socket, transport=Transport,
		handler=Handler},
   handler_init(State, Req, HandlerOpts).

handler_init(State=#state{socket=Socket, transport=Transport,
      handler=Handler}, Req, HandlerOpts) ->
   {ok, Req2, HandlerState} = Handler:websocket_init(Transport:name(), Req, HandlerOpts),
   %% Flush the resp_sent message before moving on.
   receive {cowboy_req, resp_sent} -> ok after 0 -> ok end,
   State2 = handler_loop_timeout(State),
   handler_before_loop(State2#state{key=undefined,
      messages=Transport:messages()}, Req2, HandlerState, <<>>).

handler_before_loop(State=#state{
         socket=Socket, transport=Transport, hibernate=true},
      Req, HandlerState, SoFar) ->
   lager:info("~16w http_rev_proxy_websocket:handler_before_loop1", [self()]),
   Transport:setopts(Socket, [{active, once}]),
   {suspend, ?MODULE, handler_loop,
      [State#state{hibernate=false}, Req, HandlerState, SoFar]};
handler_before_loop(State=#state{socket=Socket, transport=Transport},
      Req, HandlerState, SoFar) ->
   lager:info("~16w http_rev_proxy_websocket:handler_before_loop2", [self()]),
   Transport:setopts(Socket, [{active, once}]),
   handler_loop(State, Req, HandlerState, SoFar).

handler_loop_timeout(State=#state{timeout=infinity}) ->
   State#state{timeout_ref=undefined};
handler_loop_timeout(State=#state{timeout=Timeout, timeout_ref=PrevRef}) ->
   _ = case PrevRef of undefined -> ignore; PrevRef ->
      erlang:cancel_timer(PrevRef) end,
   TRef = erlang:start_timer(Timeout, self(), ?MODULE),
   State#state{timeout_ref=TRef}.

handler_loop(State=#state{socket=Socket, messages={OK, Closed, Error},
      timeout_ref=TRef}, Req, HandlerState, SoFar) ->
   lager:info("~16w http_rev_proxy_websocket:handler_loop", [self()]),
   receive
      {OK, Socket, Data} ->
         State2 = handler_loop_timeout(State),
         websocket_data(State2, Req, HandlerState,
            << SoFar/binary, Data/binary >>);
      {Closed, Socket} ->
         lager:info("~16w Closed ~p, Socket ~p", [self(), Closed, Socket]),
         handler_terminate(State, Req, HandlerState, {error, closed});
      {Error, Socket, Reason} ->
         lager:info("~16w Error ~p, Socket ~p, Reason ~p", [self(), Error, Socket, Reason]),
         handler_terminate(State, Req, HandlerState, {error, Reason});
      {timeout, TRef, ?MODULE} ->
         websocket_close(State, Req, HandlerState, {normal, timeout});
      {timeout, OlderTRef, ?MODULE} when is_reference(OlderTRef) ->
         handler_loop(State, Req, HandlerState, SoFar);
      Message ->
         handler_call(State, Req, HandlerState,
            SoFar, websocket_info, Message, fun handler_before_loop/4)
   end.

websocket_data(State, Req, HandlerState, Data) ->
   lager:info("~16w http_rev_proxy_websocket:handler_call", [self()]),
   handler_call(State, Req, HandlerState, <<>>,
      websocket_handle, Data, fun handler_before_loop/4).

handler_call(State=#state{handler=Handler}, Req, HandlerState,
      RemainingData, Callback, Message, NextState) ->
   lager:info("~16w http_rev_proxy_websocket:handler_call", [self()]),
   lager:info("~16w ~p:~p - Message: ~p", [self(), Handler, Callback, Message]),
   try Handler:Callback(Message, Req, HandlerState) of
      {ok, Req2, HandlerState2} ->
         NextState(State, Req2, HandlerState2, RemainingData);
      {ok, Req2, HandlerState2, hibernate} ->
         NextState(State#state{hibernate=true},
            Req2, HandlerState2, RemainingData);
      {reply, Payload, Req2, HandlerState2}
            when is_list(Payload) ->
         case websocket_send_many(Payload, State) of
            {ok, State2} ->
               NextState(State2, Req2, HandlerState2, RemainingData);
            {shutdown, State2} ->
               handler_terminate(State2, Req2, HandlerState2,
                  {normal, shutdown});
            {{error, _} = Error, State2} ->
               handler_terminate(State2, Req2, HandlerState2, Error)
         end;
      {reply, Payload, Req2, HandlerState2, hibernate}
            when is_list(Payload) ->
         case websocket_send_many(Payload, State) of
            {ok, State2} ->
               NextState(State2#state{hibernate=true},
                  Req2, HandlerState2, RemainingData);
            {shutdown, State2} ->
               handler_terminate(State2, Req2, HandlerState2,
                  {normal, shutdown});
            {{error, _} = Error, State2} ->
               handler_terminate(State2, Req2, HandlerState2, Error)
         end;
      {reply, Payload, Req2, HandlerState2} ->
         case websocket_send(Payload, State) of
            {ok, State2} ->
               NextState(State2, Req2, HandlerState2, RemainingData);
            {shutdown, State2} ->
               handler_terminate(State2, Req2, HandlerState2,
                  {normal, shutdown});
            {{error, _} = Error, State2} ->
               handler_terminate(State2, Req2, HandlerState2, Error)
         end;
      {reply, Payload, Req2, HandlerState2, hibernate} ->
         case websocket_send(Payload, State) of
            {ok, State2} ->
               NextState(State2#state{hibernate=true},
                  Req2, HandlerState2, RemainingData);
            {shutdown, State2} ->
               handler_terminate(State2, Req2, HandlerState2,
                  {normal, shutdown});
            {{error, _} = Error, State2} ->
               handler_terminate(State2, Req2, HandlerState2, Error)
         end;
      {shutdown, Req2, HandlerState2} ->
         websocket_close(State, Req2, HandlerState2, {normal, shutdown})
   catch Class:Reason ->
      _ = websocket_close(State, Req, HandlerState, {error, handler}),
      erlang:Class([
         {reason, Reason},
         {mfa, {Handler, Callback, 3}},
         {stacktrace, erlang:get_stacktrace()},
         {msg, Message},
         {req, cowboy_req:to_list(Req)},
         {state, HandlerState}
      ])
   end.

websocket_opcode(text) -> 1;
websocket_opcode(binary) -> 2;
websocket_opcode(close) -> 8;
websocket_opcode(ping) -> 9;
websocket_opcode(pong) -> 10.

websocket_send(Data, State=#state{socket=Socket, transport=Transport}) ->
   lager:info("~16w http_rev_proxy_websocket:websocket_send", [self()]),
   case Transport:send(Socket, Data) of
      ok -> {shutdown, State};
      Error -> {Error, State}
   end.

websocket_send_many([], State) ->
   lager:info("~16w http_rev_proxy_websocket:websocket_send_many", [self()]),
   {ok, State};
websocket_send_many([Frame|Tail], State) ->
   lager:info("~16w http_rev_proxy_websocket:websocket_send_many", [self()]),
   case websocket_send(Frame, State) of
      {ok, State2} -> websocket_send_many(Tail, State2);
      {shutdown, State2} -> {shutdown, State2};
      {Error, State2} -> {Error, State2}
   end.

websocket_close(State=#state{socket=Socket, transport=Transport},
      Req, HandlerState, Reason) ->
   lager:info("~16w http_rev_proxy_websocket:websocket_close", [self()]),
   case Reason of
      {normal, _} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:1, 2:7, 1000:16 >>);
      {error, badframe} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:1, 2:7, 1002:16 >>);
      {error, badencoding} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:1, 2:7, 1007:16 >>);
      {error, handler} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:1, 2:7, 1011:16 >>);
      {remote, closed} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:8 >>);
      {remote, Code, _} ->
         Transport:send(Socket, << 1:1, 0:3, 8:4, 0:1, 2:7, Code:16 >>)
   end,
   handler_terminate(State, Req, HandlerState, Reason).

handler_terminate(#state{env=Env, handler=Handler},
      Req, HandlerState, TerminateReason) ->
   lager:info("~16w http_rev_proxy_websocket:handler_terminate - Reason: ~p", [self(), TerminateReason]),
   try
      Handler:websocket_terminate(TerminateReason, Req, HandlerState)
   catch Class:Reason ->
      erlang:Class([
         {reason, Reason},
         {mfa, {Handler, websocket_terminate, 3}},
         {stacktrace, erlang:get_stacktrace()},
         {req, cowboy_req:to_list(Req)},
         {state, HandlerState},
         {terminate_reason, TerminateReason}
      ])
   end,
   {ok, Req, [{result, closed}|Env]}.
