-module(http_proxy_connection).

-behaviour(gen_fsm).

%% public API
-export([start/2, start_link/2, received_message/2]).
%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4,
         % custom state names
         idle/2, wait_for_more/2]).

%%% PUBLIC API
start(Socket, Transport) ->
   gen_fsm:start(?MODULE, [Socket, Transport], []).
 
start_link(Socket, Transport) ->
   gen_fsm:start_link(?MODULE, [Socket, Transport], []).

received_message(Pid, Message) ->
   gen_fsm:send_event(Pid, {received_message, Message}).

-record(state, {name="",
                socket,
                transport,
                message}).

init([Socket, Transport]) ->
  lager:info ("State machine created", []),
   {ok, idle, #state{socket=Socket, transport=Transport}}.

%% Note: DO NOT reply to unexpected calls. Let the call-maker crash!
handle_sync_event(Event, _From, StateName, Data) ->
   unexpected(Event, StateName),
   {next_state, StateName, Data}.

handle_info(_Info, _StateName, StateData) -> 
   {noreply, StateData}.

%% The other player has sent this cancel event
%% stop whatever we're doing and shut down!
handle_event(received_message, _StateName, S=#state{}) ->
  notice(S, "received message", []),
  {stop, other_cancelled, S};

handle_event(Event, StateName, Data) ->
  unexpected(Event, StateName),
  {next_state, StateName, Data}.

code_change(_OldVsn, StateName, StateData, _Extra) -> 
  {ok, StateName, StateData}.

%% Transaction completed.
terminate(normal, ready, S=#state{}) ->
  notice(S, "FSM leaving.", []);

terminate(_Reason, _StateName, _StateData) ->
  ok.

idle({received_message, Message}, S=#state{}) ->
   notice(S, "received message ~p", [Message]),
   {next_state, wait_for_more, S#state{message=Message}};
idle(Event, Data) ->
   unexpected(Event, idle),
   {next_state, idle, Data}.

wait_for_more({received_message, Message}, S=#state{}) ->
   notice(S, "received message ~p", [Message]),
   {next_state, wait_for_more, S#state{message=Message}};
wait_for_more(Event, Data) ->
   unexpected(Event, idle),
   {next_state, idle, Data}.

%% Send players a notice. This could be messages to their clients
%% but for our purposes, outputting to the shell is enough.
notice(#state{name=N}, Str, Args) ->
  io:format("~s: "++Str++"~n", [N|Args]).
 
%% Unexpected allows to log unexpected messages
unexpected(Msg, State) ->
  io:format("~p received unknown event ~p while in state ~p~n",
  [self(), Msg, State]).