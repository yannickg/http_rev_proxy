-module(http_proxy_connection).

-behaviour(gen_fsm).

%% public API
-export([start/2, start_link/2, connect/2, received_data/2]).
%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4,
         % custom state names
         idle/2, idle/3]).

%%% PUBLIC API
start(Socket, Transport) ->
   gen_fsm:start(?MODULE, [Socket, Transport], []).
 
start_link(Socket, Transport) ->
   gen_fsm:start_link(?MODULE, [Socket, Transport], []).

connect(OwnPid, Data) ->
   gen_fsm:send_event(OwnPid, {connect, Data}).

received_data(OwnPid, Data) ->
   gen_fsm:send_event(OwnPid, {received_data, Data}).

notify_cancel(OtherPid) ->
  gen_fsm:send_all_state_event(OtherPid, cancel).

-record(state, {name="",
                socket,
                transport,
                other,
                ownitems=[],
                otheritems=[],
                monitor,
                from}).

init([Socket, Transport]) ->
   {ok, idle, #state{socket=Socket, transport=Transport}}.

%% This cancel event comes from the client. We must warn the other
%% player that we have a quitter!
handle_sync_event(cancel, _From, _StateName, S = #state{}) ->
   notify_cancel(S#state.other),
   notice(S, "cancelling trade, sending cancel event", []),
   {stop, cancelled, ok, S};

%% Note: DO NOT reply to unexpected calls. Let the call-maker crash!
handle_sync_event(Event, _From, StateName, Data) ->
   unexpected(Event, StateName),
   {next_state, StateName, Data}.

handle_info(_Info, _StateName, StateData) -> 
   {noreply, StateData}.

%% The other player has sent this cancel event
%% stop whatever we're doing and shut down!
handle_event(received_data, _StateName, S=#state{}) ->
  notice(S, "received cancel event", []),
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

idle({connect, OtherPid}, S=#state{}) ->
   Ref = monitor(process, OtherPid),
   notice(S, "~p asked for a trade negotiation", [OtherPid]),
   {next_state, idle_wait, S#state{other=OtherPid, monitor=Ref}};
idle({received_data, OtherPid}, S=#state{}) ->
   Ref = monitor(process, OtherPid),
   notice(S, "~p asked for a trade negotiation", [OtherPid]),
   {next_state, idle_wait, S#state{other=OtherPid, monitor=Ref}};
idle(Event, Data) ->
   unexpected(Event, idle),
   {next_state, idle, Data}.

idle({negotiate, OtherPid}, From, S=#state{}) ->
   % ask_negotiate(OtherPid, self()),
   notice(S, "asking user ~p for a trade", [OtherPid]),
   Ref = monitor(process, OtherPid),
   {next_state, idle_wait, S#state{other=OtherPid, monitor=Ref, from=From}};
idle(Event, _From, Data) ->
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