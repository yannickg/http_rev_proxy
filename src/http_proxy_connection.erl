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

-module(http_proxy_connection).

-behaviour(gen_fsm).

%% public API
-export([start/1, start_link/1, received_request/2, received_response/2, client_disconnected/1, server_disconnected/1]).
%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4,
         % custom state names
         initial/2, connected/2, disconnected/2]).
%% private API
-export([server_listener/1]).

%%% PUBLIC API
start(CallbackPid) ->
   gen_fsm:start(?MODULE, [CallbackPid], []).
 
start_link(CallbackPid) ->
   gen_fsm:start_link(?MODULE, [CallbackPid], []).

received_request(Pid, Request) ->
   gen_fsm:send_event(Pid, {received_request, Request}).

received_response(Pid, Request) ->
   gen_fsm:send_event(Pid, {received_response, Request}).

client_disconnected(Pid) ->
   gen_fsm:send_event(Pid, client_disconnected).

server_disconnected(Pid) ->
   gen_fsm:send_event(Pid, server_disconnected).

-record(state, {
                  callback_pid,
                  socket
               }).

init([CallbackPid]) ->
   {ok, initial, #state{callback_pid=CallbackPid}}.

%% Note: DO NOT reply to unexpected calls. Let the call-maker crash!
handle_sync_event(Event, _From, StateName, Data) ->
   unexpected(Event, StateName),
   {next_state, StateName, Data}.

handle_info(_Info, _StateName, State) -> 
   lager:info("handle_info:_Info", []),
   {noreply, State}.

handle_event(Event, StateName, Data) ->
  unexpected(Event, StateName),
  {next_state, StateName, Data}.

code_change(_OldVsn, StateName, State, _Extra) -> 
  {ok, StateName, State}.

%% Transaction completed.
terminate(normal, ready, _State=#state{}) ->
  lager:info("FSM leaving.", []);

terminate(_Reason, _StateName, _State) ->
  ok.

server_listener(CallbackPid) ->
   receive
      {tcp, Socket, Data} ->
         http_proxy_connection:received_response(CallbackPid, Data),
         inet:setopts(Socket, [{active, once}]),
         server_listener(CallbackPid);
      {tcp_closed, _Socket} ->
         http_proxy_connection:server_disconnected(CallbackPid);
      {tcp_error, _Socket, _Reason} ->
         http_proxy_connection:server_disconnected(CallbackPid)
   end.

proxied_server(_Req) ->
   {"www.google.com", 80, <<"www.google.com">>}.

initial({received_request, Req}, State=#state{callback_pid=CallbackPid}) ->
   {Hostname, Port, Header} = proxied_server(Req),
   case gen_tcp:connect(Hostname, Port, [binary, {active, once}, {nodelay, true}, {reuseaddr, true}]) of
      {ok, Socket} ->
         Pid = spawn_link(?MODULE, server_listener, [self()]),
         gen_tcp:controlling_process(Socket, Pid),

         % Rewrite headers.
         Req2 = http_rev_proxy_request:replace_header(<<"host">>, Header, Req),
         {Packet, _Req3} = http_rev_proxy_request:build_packet(Req2),
         gen_tcp:send(Socket, Packet),
         {next_state, connected, State#state{socket=Socket}};
      {error, Reason} ->
         CallbackPid ! {connection_failed, Reason},
         {next_state, disconnected, State}
   end;

initial(client_disconnected, State) ->
   % do nothing
   {next_state, disconnected, State};

initial(Event, Data) ->
   unexpected(Event, initial),
   {next_state, initial, Data}.

connected({received_request, Req}, State=#state{socket=Socket}) ->
   gen_tcp:send(Socket, Req),
   {next_state, connected, State};

connected({received_response, Response}, State=#state{callback_pid=CallbackPid}) ->
   CallbackPid ! {received_response, Response},
   {next_state, connected, State};

connected(client_disconnected, State=#state{socket=Socket}) ->
   ok = gen_tcp:close(Socket),
   {next_state, disconnected, State};

connected(server_disconnected, State=#state{callback_pid=CallbackPid}) ->
   CallbackPid ! {server_disconnected},
   {next_state, disconnected, State};

connected(Event, Data) ->
   unexpected(Event, connected),
   {next_state, connected, Data}.

disconnected(Event, Data) ->
   unexpected(Event, disconnected),
   {next_state, disconnected, Data}.

%% Unexpected allows to log unexpected messages
unexpected(Msg, State) ->
  io:format("~p received unknown event ~p while in state ~p~n",
              [self(), Msg, State]).
