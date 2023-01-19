%%%-------------------------------------------------------------------
%%% @doc
%%% LRU Repository for Flag and Segment configuration
%%% @end
%%%-------------------------------------------------------------------

-module(cfclient_cache_repository).

-include_lib("kernel/include/logger.hrl").

-include("cfclient_config.hrl").

-export([get_from_cache/2, set_to_cache/3, set_pid/1, get_pid/0]).

-type flag() :: {flag, Identifier :: binary()}.
-type segment() :: {segment, Identifier :: binary()}.

% TODO export types?

% @doc Get flag or segment from cache.
-spec get_from_cache(flag() | segment(), pid()) ->
    cfapi_feature_config:cfapi_feature_config() | cfapi_segment:cfapi_segment() |
    undefined.
get_from_cache({Type, Identifier}, CachePID) ->
  FlagKey = format_key({Type, Identifier}),
  get(CachePID, FlagKey).

-spec get(pid(), binary()) -> term().
get(CachePID, FlagKey) ->
  lru:get(CachePID, FlagKey).

% @doc Place flag or segment into cache with new value
-spec set_to_cache(flag() | segment(), cfapi_feature_config:cfapi_feature_config() | cfapi_segment:cfapi_segment() , CachePID :: pid()) -> atom().
set_to_cache({Type, Identifier}, Feature,  CachePID) ->
  IsOutdated = is_outdated({Type, Identifier}, Feature, CachePID),
  FlagKey = format_key({Type, Identifier}),
  case set(CachePID, FlagKey, Feature, IsOutdated) of
    ok ->
      ?LOG_DEBUG("Updated ~p~n Type with ~p~n Identifier:", [Type, Identifier]);
    not_ok ->
      ?LOG_ERROR("Did not update cache: requested ~p~n was outdated. Identifier: ~p~n", [Type, Identifier]),
      not_ok
  end.

-spec set(pid(), binary(), cfapi_feature_config:cfapi_feature_config() | cfapi_segment:cfapi_segment(), boolean()) -> atom().
set(CachePID, Identifier, Value, false) ->
  lru:add(CachePID, Identifier, Value),
  ok;
%% Don't place in cache if outdated. Note: if this happens we treat is as an error state as
%% it should not happen, so log an error to the user.
set(_, _, _, true) ->
  not_ok.

-spec is_outdated(
  flag() | segment(),
  cfapi_feature_config:cfapi_feature_config() | cfapi_segment:cfapi_segment(), pid()
) ->
  boolean().
is_outdated({flag, Identifier}, Feature, CachePID) ->
  case get_from_cache({flag, Identifier}, CachePID) of
    undefined -> false;

    OldFeature ->
      #{version := OldFeatureVersion} = OldFeature,
      #{version := NewFeatureVersion} = Feature,
      OldFeatureVersion > NewFeatureVersion
  end;

is_outdated({segment, Identifier}, Segment, CachePID) ->
  case get_from_cache({segment, Identifier}, CachePID) of
    undefined -> false;

    OldSegment ->
      #{version := OldSegmentVersion} = OldSegment,
      #{version := NewSegmentVersion} = Segment,
      OldSegmentVersion > NewSegmentVersion
  end.

% Create binary key from flag or segment
-spec format_key(flag() | segment()) -> binary().
format_key({flag, Identifier}) -> <<"flags/", Identifier/binary>>;
format_key({segment, Identifier}) -> <<"segments/", Identifier/binary>>.

-spec set_pid(CachePID :: pid()) -> ok.
set_pid(CachePID) ->
  application:set_env(cfclient, cachepid, CachePID).

-spec get_pid() -> pid().
get_pid() ->
  {ok, Pid} = application:get_env(cfclient, cachepid),
  Pid.
