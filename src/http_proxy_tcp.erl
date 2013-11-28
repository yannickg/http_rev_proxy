-module(http_proxy_tcp).

-behavior(gen_server).

-export([start_link/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Num, LPort) ->
    start_link([]).

start_link(Args) ->
    io:format("Entering server"),
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

% This is called when a connection is made to the server
init(Options) ->
    io:format("Init server"),
    LPort = proplists:get_value(port, Options),
    case gen_tcp:listen(LPort,[{active, false},{packet,2}]) of
        {ok, ListenSock} ->
            Num = proplists:get_value(num, Options),
            start_servers(Num,ListenSock),
            {ok, Port} = inet:port(ListenSock),
            Port;
        {error,Reason} ->
            {error,Reason}
    end.

% handle_call is invoked in response to gen_server:call
handle_call({checkout, Who, Book}, _From, Library) ->
    Response = case dict:is_key(Book, Library) of
        true ->
            NewLibrary = Library,
            {already_checked_out, Book};
        false ->
            NewLibrary = dict:append(Book, Who, Library),
            ok
    end,
    {reply, Response, NewLibrary};

handle_call({lookup, Book}, _From, Library) ->
    Response = case dict:is_key(Book, Library) of
        true ->
            {who, lists:nth(1, dict:fetch(Book, Library))};
        false ->
            {not_checked_out, Book}
    end,
    {reply, Response, Library};

handle_call({return, Book}, _From, Library) ->
    NewLibrary = dict:erase(Book, Library),
    {reply, ok, NewLibrary};

handle_call(_Message, _From, Library) ->
    {reply, error, Library}.

% We get compile warnings from gen_server unless we define these
handle_cast(_Message, Library) -> {noreply, Library}.
handle_info(_Message, Library) -> {noreply, Library}.
terminate(_Reason, _Library) -> ok.
code_change(_OldVersion, Library, _Extra) -> {ok, Library}.

start_servers(0,_) ->
    ok;
start_servers(Num,LS) ->
    spawn(?MODULE,server,[LS]),
    start_servers(Num-1,LS).

server(LS) ->
    case gen_tcp:accept(LS) of
        {ok,S} ->
            loop(S),
            server(LS);
        Other ->
            io:format("accept returned ~w - goodbye!~n",[Other]),
            ok
    end.

loop(S) ->
    inet:setopts(S,[{active,once}]),
    receive
        {tcp,S,Data} ->
            Answer = process(Data),
            gen_tcp:send(S,Answer),
            loop(S);
        {tcp_closed,S} ->
            io:format("Socket ~w closed [~w]~n",[S,self()]),
            ok
    end.    

    process(Data) ->
        Data.