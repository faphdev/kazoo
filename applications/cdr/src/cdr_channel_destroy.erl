%%%-------------------------------------------------------------------
%%% @copyright (C) 2010-2014, 2600Hz
%%% @doc
%%% Listen for CDR events and record them to the database
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%   Edouard Swiac
%%%   Ben Wann
%%%-------------------------------------------------------------------
-module(cdr_channel_destroy).

-include("cdr.hrl").

-export([handle_req/2]).

handle_req(JObj, _Props) ->
    'true' = wapi_call:event_v(JObj),
    _ = wh_util:put_callid(JObj),
    AccountId = wh_json:get_value([<<"Custom-Channel-Vars">>,<<"Account-ID">>], JObj),
    Timestamp = wh_json:get_integer_value(<<"Timestamp">>, JObj),
    prepare_and_save(AccountId, Timestamp, JObj).

-spec prepare_and_save(account_id(), pos_integer(), wh_json:object()) -> wh_json:object().
prepare_and_save(AccountId, Timestamp, JObj) ->
    Routines = [fun normalize/3
                ,fun update_pvt_parameters/3
                ,fun update_ccvs/3
                ,fun set_doc_id/3
                ,fun set_recording_url/3
                ,fun save_cdr/3
               ],
    lists:foldl(fun(F, J) ->
                        F(AccountId, Timestamp, J)
                end, JObj, Routines).

-spec normalize(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
normalize(_, _, JObj) ->
    wh_json:normalize_jobj(JObj).

-spec update_pvt_parameters(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
update_pvt_parameters('undefined', _, JObj) ->
    Props = [{'type', 'cdr'}
             ,{'crossbar_doc_vsn', 2}
            ],
    wh_doc:update_pvt_parameters(JObj, ?WH_ANONYMOUS_CDR_DB, Props);
update_pvt_parameters(AccountId, Timestamp, JObj) ->
    AccountMODb = wh_util:format_account_id(AccountId, Timestamp),
    Props = [{'type', 'cdr'}
             ,{'crossbar_doc_vsn', 2}
             ,{'account_id', AccountId}
            ],
    wh_doc:update_pvt_parameters(JObj, AccountMODb, Props).

-spec update_ccvs(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
update_ccvs(_, _, JObj) ->
    CCVs = wh_json:get_value(<<"custom_channel_vars">>, JObj, wh_json:new()),
    {UpdatedJobj, UpdatedCCVs} =
        wh_json:foldl(
            fun update_ccvs_foldl/3
            ,{JObj, CCVs}
            ,CCVs
        ),
    wh_json:set_value(<<"custom_channel_vars">>, UpdatedCCVs, UpdatedJobj).

-spec update_ccvs_foldl(ne_binary(), any(), {wh_json:object(), wh_json:object()}) -> {wh_json:object(), wh_json:object()}.
update_ccvs_foldl(Key, Value,  {JObj, CCVs}=Acc) ->
    case wh_json:is_private_key(Key) of
        'false' -> Acc;
        'true' ->
            {wh_json:set_value(Key, Value, JObj)
             ,wh_json:delete_key(Key, CCVs)}
    end.


-spec set_doc_id(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
set_doc_id(_, Timestamp, JObj) ->
    CallId = wh_json:get_value(<<"call_id">>, JObj),
    DocId = cdr_util:get_cdr_doc_id(Timestamp, CallId),
    wh_json:set_value(<<"_id">>, DocId, JObj).

-spec set_recording_url(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
set_recording_url(_, _, JObj) ->
    case wh_json:get_value([<<"custom_channel_vars">>, <<"recording_url">>], JObj) of
        'undefined' -> JObj;
        Url -> wh_json:set_value(<<"recording_url">>, Url, JObj)
    end.

-spec save_cdr(api_binary(), pos_integer(), wh_json:object()) -> wh_json:object().
save_cdr(_, _, JObj) ->
    CDRDb = wh_json:get_value(<<"pvt_account_db">>, JObj),
    case cdr_util:save_cdr(CDRDb, JObj) of
        {'error', 'max_retries'} ->
            lager:error("write failed to ~s, too many retries", [CDRDb]);
        'ok' -> 'ok'
    end.

