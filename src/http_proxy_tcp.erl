-module(http_proxy_tcp).

-behavior(gen_server).

%% public API
-export([start_link/2, tcp_open/3, tcp_message/4, tcp_close/3]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Num, Port) ->
   gen_server:start_link({local, ?MODULE}, ?MODULE, [Num, Port], []).

tcp_open(Pid, Socket, Transport) ->
   gen_server:call(Pid, {tcp_open, Socket, Transport}).

tcp_message(Pid, Socket, Transport, Message) ->
   gen_server:call(Pid, {tcp_message, Socket, Transport, Message}).

tcp_close(Pid, Socket, Transport) ->
   gen_server:call(Pid, {tcp_close, Socket, Transport}).

-record(connection, {
                  state_machine_pid,
                  buffer = <<>>
               }).
-record(state, {
                  connections = dict:new()
               }).

% This is called when a connection is made to the server
init([Num, Port]) ->
   {ok, _} = ranch:start_listener(http_proxy, Num,
      ranch_tcp, [{port, Port}], http_proxy_protocol, []),
   ranch:set_protocol_options(http_proxy, [{http_proxy_tcp, self()}]),
   {ok, #state{connections=dict:new()}}.

% handle_call is invoked in response to gen_server:call
handle_call({tcp_open, Socket, _Transport}, _From, State) ->

   % Create State Machine
   {ok, Pid} = http_proxy_connection:start_link(Socket),
   Connection = #connection{state_machine_pid = Pid},
   {reply, ok, State#state{connections = dict:store(Socket, Connection, State#state.connections)}};

handle_call({tcp_message, Socket, _Transport, Message}, _From, State) ->

   % Send state machine new data
   Connection = dict:fetch(Socket, State#state.connections),
   Buffer = Connection#connection.buffer,
   NewBuffer = framer(Connection#connection.state_machine_pid, << Buffer/binary, Message/binary >> ),
   % Transport:send(Socket, Data),
   {reply, ok, State};

handle_call({tcp_close, Socket, _Transport}, _From, State) ->

   % Send state machine new data
   Connection = dict:fetch(Socket, State#state.connections),
   http_proxy_connection:client_disconnected(Connection#connection.state_machine_pid),
   {reply, ok, State};

handle_call(_Message, _From, State) ->
    {reply, error, State}.

% We get compile warnings from gen_server unless we define these
handle_cast(_Message, State) -> {noreply, State}.
handle_info(_Message, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVersion, State, _Extra) -> {ok, State}.

framer(CallbackPid, Message) ->
   parse_request(Message, 0),
   http_proxy_connection:received_request(CallbackPid, Message),
   ok.

parse_request(<< $\n, _/binary >>, _) ->
   lager:info("error");
%% We limit the length of the Request-line to MaxLength to avoid endlessly
%% reading from the socket and eventually crashing.
parse_request(Buffer, ReqEmpty) ->
   lager:info("parse_request - Buffer: ~p", [Buffer]),
   case match_eol(Buffer, 0) of
      nomatch when byte_size(Buffer) > 4096 ->
            lager:info("parse_request error: buffer too large");
      nomatch ->
            lager:info("parse_request: need more");
      1 when ReqEmpty =:= 5 ->
            lager:info("parse_request error: empty request");
      1 ->
            << _:16, Rest/binary >> = Buffer,
            parse_request(Rest, ReqEmpty + 1);
      _ ->
            parse_method(Buffer, <<>>)
   end.

match_eol(<< $\n, _/bits >>, N) ->
   lager:info("match_eol - N: ~p", [N]),
   N;
match_eol(<< _, Rest/bits >>, N) ->
   lager:info("match_eol - N: ~p - Rest: ~p", [N, Rest]),
   match_eol(Rest, N + 1);
match_eol(_, _) ->
   lager:info("match_eol: nomatch"),
   nomatch.

parse_method(<< C, Rest/bits >>, SoFar) ->
   lager:info("parse_method - C:~p -Rest: ~p - SoFar: ~p", [C, Rest, SoFar]),
   case C of
      $\r -> lager:info("parse_method error");
      $\s -> parse_uri(Rest, SoFar);
      _ -> parse_method(Rest, << SoFar/binary, C >>)
   end.

parse_uri(Buffer, Method) ->
   lager:info("parse_uri - Buffer: ~p - Method: ~p", [Buffer, Method]).

