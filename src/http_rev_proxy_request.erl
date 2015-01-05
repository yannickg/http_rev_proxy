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
-export([rewrite_header/3]).
-export([socket_requires_options/1]).
-export([build_packet/1]).

-record(http_rev_proxy_req, {
   cowboy_req
}).

new(Req) ->
	#http_rev_proxy_req{cowboy_req=Req}.

rewrite_header(Key, Value, #http_rev_proxy_req{cowboy_req=Req}) ->
	{Headers, Req2} = cowboy_req:headers(Req),
	NewHeaders = lists:keyreplace(Key, 1, Headers, {Key, Value}),
	Req3 = cowboy_req:set([{headers, NewHeaders}], Req2),
	#http_rev_proxy_req{cowboy_req=Req3}.

headers_fixup(true, Req) ->
   {Headers, Req2} = cowboy_req:headers(Req),
   NewHeaders = lists:keydelete(<<"cookie">>, 1, Headers),
   lager:info("************NewHeaders: ~p", [NewHeaders]),
   cowboy_req:set([{headers, NewHeaders}], Req2);
headers_fixup(false, Req) ->
   Req.

socket_requires_options(#http_rev_proxy_req{cowboy_req=Req}) ->
   request_is_websocket(Req).

request_is_websocket(Req) ->
   {Headers, _} = cowboy_req:headers(Req),
   case lists:keyfind(<<"upgrade">>, 1, Headers) of
      {_Key, _Value} ->
         true;
      _ ->
         false
   end.

build_packet(#http_rev_proxy_req{cowboy_req=Req}) ->
   lager:info("http_rev_proxy_request:build_packet", []),
   {Version, Req2} = cowboy_req:version(Req),
   {Method, Req3} = cowboy_req:method(Req2),
   {Path, Req4} = cowboy_req:path(Req3),
   Req5 = headers_fixup(request_is_websocket(Req4), Req4),
   {Headers, Req6} = cowboy_req:headers(Req5),

   HTTPVer = atom_to_binary(Version, latin1),

	RequestLine = << Method/binary, " ",
		Path/binary, " ", HTTPVer/binary, "\r\n" >>,
	HeaderLines = [[Key, <<": ">>, Value, <<"\r\n">>]
		|| {Key, Value} <- Headers],
	{[RequestLine, HeaderLines, <<"\r\n">>], #http_rev_proxy_req{cowboy_req=Req6}}.
