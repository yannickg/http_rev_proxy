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
-export([loop/1]).

%%% PUBLIC API
start(Socket) ->
   gen_fsm:start(?MODULE, [Socket], []).
 
start_link(Socket) ->
   gen_fsm:start_link(?MODULE, [Socket], []).

received_request(Pid, Request) ->
   gen_fsm:send_event(Pid, {received_request, Request}).

received_response(Pid, Request) ->
   gen_fsm:send_event(Pid, {received_response, Request}).

client_disconnected(Pid) ->
   gen_fsm:send_event(Pid, client_disconnected).

server_disconnected(Pid) ->
   gen_fsm:send_event(Pid, server_disconnected).

-record(state, {client_socket,
                server_socket,
                message}).

init([Socket]) ->
   {ok, initial, #state{client_socket=Socket}}.

%% Note: DO NOT reply to unexpected calls. Let the call-maker crash!
handle_sync_event(Event, _From, StateName, Data) ->
   unexpected(Event, StateName),
   {next_state, StateName, Data}.

handle_info(_Info, _StateName, State) -> 
   lager:info("handle_info:_Info", []),
   {noreply, State}.

%% The other player has sent this cancel event
%% stop whatever we're doing and shut down!
handle_event(received_request, _StateName, S=#state{}) ->
   lager:info("received request", []),
   {stop, other_cancelled, S};

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

loop(Pid) ->
   receive
      {tcp, Socket, Data} ->
         http_proxy_connection:received_response(Pid, Data),
         inet:setopts(Socket, [{active, once}]);
      {tcp_closed, _Socket} ->
         ok;
      {tcp_error, _Socket, Reason} ->
         lager:info("handle_info:tcp_error - ~p", [Reason])
   end,

   loop(Pid).

initial({received_request, Request}, State=#state{}) ->

   % make decision here.
   Pid = spawn_link(?MODULE, loop, [self()]),
   {ok, Socket} = gen_tcp:connect("google.com", 80, [binary, {active, once}, {nodelay, true}, {reuseaddr, true}]),
   gen_tcp:controlling_process(Socket, Pid),

   gen_tcp:send(Socket, Request),

   {next_state, connected, State#state{server_socket=Socket}};

initial(client_disconnected, State=#state{}) ->
   gen_tcp:close(State#state.client_socket),
   {next_state, disconnected, State};

initial(Event, Data) ->
   unexpected(Event, initial),
   {next_state, initial, Data}.

connected({received_request, Request}, State) ->
   gen_tcp:send(State#state.server_socket, Request),
   {next_state, connected, State#state{message=Request}};

connected({received_response, Response}, State) ->
   gen_tcp:send(State#state.client_socket, Response),
   {next_state, connected, State#state{message=Response}};

connected(client_disconnected, State) ->
   ok = gen_tcp:close(State#state.client_socket),
   ok = gen_tcp:close(State#state.server_socket),
   {next_state, disconnected, State};

connected(server_disconnected, State) ->
   ok = gen_tcp:close(State#state.server_socket),
   ok = gen_tcp:close(State#state.client_socket),
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
