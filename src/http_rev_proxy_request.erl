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

-module(http_rev_proxy_request).

%% Request API.
-export([new/1]).
-export([replace_header/3]).
-export([request_is_websocket/1]).
-export([build_packet/1]).
-export([set_status_code/2]).
-export([get_content_length/1]).
-export([set_content_length/2]).
-export([set_headers/2]).
-export([set_body/2]).
-export([headers_already_parsed/1]).
-export([reply/1]).

-record(http_rev_proxy_req, {
   status_code,
   content_length = 0,
   headers = [],
   body = <<>>,
   cowboy_req
}).

new(Req) ->
	#http_rev_proxy_req{cowboy_req=Req}.

replace_header(Key, Value, #http_rev_proxy_req{cowboy_req=Req}) ->
	{Headers, Req2} = cowboy_req:headers(Req),
	NewHeaders = lists:keyreplace(Key, 1, Headers, {Key, Value}),
	Req3 = cowboy_req:set([{headers, NewHeaders}], Req2),
	#http_rev_proxy_req{cowboy_req=Req3}.

request_is_websocket(#http_rev_proxy_req{cowboy_req=Req}) ->
   {Headers, _} = cowboy_req:headers(Req),
   case lists:keyfind(<<"upgrade">>, 1, Headers) of
      {_Key, _Value} ->
         true;
      _ ->
         false
   end.

build_packet(#http_rev_proxy_req{cowboy_req=Req}) ->
   {Version, Req2} = cowboy_req:version(Req),
   {Method, Req3} = cowboy_req:method(Req2),
   {Path, Req4} = cowboy_req:path(Req3),
   {Headers, Req5} = cowboy_req:headers(Req4),

   HTTPVer = atom_to_binary(Version, latin1),

	RequestLine = << Method/binary, " ",
		Path/binary, " ", HTTPVer/binary, "\r\n" >>,
	HeaderLines = [[Key, <<": ">>, Value, <<"\r\n">>]
		|| {Key, Value} <- Headers],
	{[RequestLine, HeaderLines, <<"\r\n">>], #http_rev_proxy_req{cowboy_req=Req5}}.

set_status_code(StatusCode, Req) ->
   Req#http_rev_proxy_req{status_code=binary_to_integer(StatusCode)}.

get_content_length(#http_rev_proxy_req{content_length=ContentLength}) ->
   ContentLength.

set_content_length(ContentLength, Req) ->
   Req#http_rev_proxy_req{content_length=ContentLength}.

set_headers(Headers, Req) ->
   Req#http_rev_proxy_req{headers=Headers}.

set_body(Body, Req) ->
   Req#http_rev_proxy_req{body=Body}.

headers_already_parsed(#http_rev_proxy_req{headers=Headers}) ->
   case Headers of
      [] ->
         no;
      _ ->
         yes
   end.

reply(#http_rev_proxy_req{status_code=StatusCode, headers=Headers, body=Body, cowboy_req=Req}) ->
   case Body of 
      <<>> ->
         cowboy_req:reply(StatusCode, Headers, Req);
      _ ->
         cowboy_req:reply(StatusCode, Headers, Body, Req)
   end.
