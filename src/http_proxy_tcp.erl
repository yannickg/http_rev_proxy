-module(http_proxy_tcp).

-behavior(gen_server).

-export([start_link/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Num, Port) ->
    io:format("Entering server~n"),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Num, Port], []).

% This is called when a connection is made to the server
init([Num, Port]) ->
    {ok, _} = ranch:start_listener(http_proxy, Num,
        ranch_tcp, [{port, Port}], http_proxy_protocol, []),
    ranch:set_protocol_options(http_proxy, [{foo, "bar"}]),
    Library = dict:new(),
    {ok, Library}.

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