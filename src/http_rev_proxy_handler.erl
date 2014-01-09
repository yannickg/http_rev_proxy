%% Feel free to use, reuse and abuse the code in this file.

%% @doc Hello world handler.
-module(http_rev_proxy_handler).

-export([init/3]).
-export([handle/2]).
-export([terminate/3]).

-record(state, {
   connection_pid
}).

init(_Type, Req, []) ->
   lager:debug("~16w http_rev_proxy_handler:init", [self()]),
   {ok, Pid} = http_proxy_connection:start_link(self()),
	{ok, Req, #state{connection_pid=Pid}}.

handle(Req, State=#state{connection_pid=ConnectionPid}) ->
   lager:debug("~16w http_rev_proxy_handler:handle", [self()]),
   ProxyReq = handle_request(ConnectionPid, Req),
   {ok, Req2} = http_rev_proxy_request:reply(ProxyReq),
   % {ok, Req2} = cowboy_req:chunked_reply(200, [], Req),
   % ok = cowboy_req:chunk("Hello\r\n", Req2),
   % ok = timer:sleep(1000),
   % ok = cowboy_req:chunk("World\r\n", Req2),
   % ok = timer:sleep(1000),
   % ok = cowboy_req:chunk("Chunked!\r\n", Req2),
	% {ok, Req2} = cowboy_req:reply(200, [
	% 	{<<"content-type">>, <<"text/plain">>}
	% ], <<"Hello Yannick!">>, Req),
	{ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
   lager:debug("~16w http_rev_proxy_handler:terminate", [self()]),
   wait_disconnection(),
	ok.

handle_request(ConnectionPid, CowboyReq) ->
   lager:debug("~16w http_rev_proxy_handler:handle_request", [self()]),
   RevProxyReq = http_rev_proxy_request:new(CowboyReq),
   http_proxy_connection:received_request(ConnectionPid, RevProxyReq),
   wait_response(RevProxyReq, <<>>).

wait_disconnection() ->
   lager:debug("~16w http_rev_proxy_handler:wait_response", [self()]),
   receive
      {server_disconnected} ->
         ok;
      {connection_failed, _Reason} ->
         % TODO: need to send 503 error
         lager:warning("~16w connection failed", [self()])
   end.

wait_response(Req, Buffer) ->
   lager:debug("~16w http_rev_proxy_handler:wait_response", [self()]),
   receive
      {received_response, Data} ->
         parse_response(Req, <<Buffer/binary, Data/binary>>);
      {server_disconnected} ->
         Req;
      {connection_failed, _Reason} ->
         % TODO: need to send 503 error
         lager:warning("~16w connection failed", [self()]),
         Req
   end.

parse_response(Req, Buffer) ->
   lager:debug("~16w http_rev_proxy_handler:parse_response", [self()]),
   case http_rev_proxy_request:headers_already_parsed(Req) of
      no ->
         {[_HttpVer, StatusCode, _Reason], Rest} = extract_status_line(Buffer),
         Req2 = http_rev_proxy_request:set_status_code(StatusCode, Req),
         Headers = extract_headers(Rest),
         case extract_content_length(Headers) of
            undefined ->
               wait_response(Req2, Buffer);
            ContentLength ->
               Req3 = http_rev_proxy_request:set_content_length(ContentLength, Req2),
               case extract_body(Buffer, ContentLength) of
                  {Headers2, undefined} ->
                     {Buffer3, Req4} = case Headers2 of
                        undefined ->
                           {Buffer, Req3};
                        _ ->
                           HeaderSize = byte_size(Headers2) + byte_size(<<"\r\n\r\n">>),
                           Length = byte_size(Buffer) - HeaderSize,
                           Buffer2 = binary:part(Buffer, {byte_size(Headers2), Length}),
                           {Buffer2, http_rev_proxy_request:set_headers(Headers, Req3)}
                     end,
                     wait_response(Req4, Buffer3);
                  {_, Body} ->
                     % populate http_rev_proxy_request body here
                     Req4 = http_rev_proxy_request:set_headers(Headers, Req3),
                     http_rev_proxy_request:set_body(Body, Req4)
               end
         end;
      yes ->
         ContentLength = http_rev_proxy_request:get_content_length(Req),
         case byte_size(Buffer) of
            ContentLength ->
               http_rev_proxy_request:set_body(Buffer, Req);
            Size when Size > ContentLength ->
               Body = binary:part(Buffer, {0, ContentLength}),
               http_rev_proxy_request:set_body(Body, Req);
            _ ->
               wait_response(Req, Buffer)
        end
   end.

extract_status_line(Buffer) ->
   lager:debug("~16w extract_status_line", [self()]),
   [StatusLine|Rest] = binary:split(Buffer, <<"\r\n">>, [global]),
   [HttpVer|[Status]] = binary:split(StatusLine, <<" ">>),
   [StatusCode|Reason] = binary:split(Status, <<" ">>),
   {[HttpVer, StatusCode, Reason], Rest}.

extract_headers(Buffer) ->
   lager:debug("~16w extract_headers", [self()]),
   Headers = lists:foldl(fun(Header, Headers) -> 
                                 Tuple = case binary:split(Header, <<": ">>) of
                                    [Key, Value] ->
                                       [{Key, Value}];
                                    _ ->
                                       []
                                 end,
                                 lists:merge(Headers, Tuple) 
                              end, 
                           [], 
                           Buffer),
   lists:reverse(Headers).

extract_content_length(Headers) ->
   lager:debug("~16w extract_content_length", [self()]),
   case lists:keyfind(<<"Content-Length">>, 1, Headers) of
      {_, ContentLength} ->
         binary_to_integer(ContentLength);
      false ->
         undefined
   end.

extract_body(Buffer, ContentLength) ->
   lager:debug("~16w extract_body", [self()]),
   case binary:split(Buffer, <<"\r\n\r\n">>) of
      [Headers|[Body]] ->
         case byte_size(Body) of
            ContentLength ->
               % lager:info("Body: ~p", [Body]),
               {Headers, Body};
            Size when Size > ContentLength ->
               % lager:info("Size: ~p", [Size]),
               {Headers, binary:part(Body, {0, ContentLength})};
            _ ->
               % lager:info("Size: ~p", [Size]),
               {Headers, undefined}
         end;
      _ ->
         {undefined, undefined}
   end.
