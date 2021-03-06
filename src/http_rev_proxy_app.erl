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

-module(http_rev_proxy_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	Dispatch = cowboy_router:compile([
		{'_', [
			{"/websocket", http_rev_proxy_ws_handler, []},
			{"/[...]", http_rev_proxy_handler, []}
		]}
	]),

	NbAcceptors = 1,
	Port = 80,
	TransOpts = [{port, Port}],
	ProtoOpts = [{env, [{dispatch, Dispatch}]}],
	{ok, _} = ranch:start_listener(http_rev_proxy, NbAcceptors,
	  ranch_tcp, TransOpts, cowboy_protocol, ProtoOpts),
    http_rev_proxy_sup:start_link().

stop(_State) ->
    ok.
