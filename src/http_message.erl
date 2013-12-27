-module(http_message).

%% public API
-export([new/1]).


-record(request, {
                  method,
                  path,
                  http_version,
                  headers = list:new()
               }).


new(Msg) ->

   ok.