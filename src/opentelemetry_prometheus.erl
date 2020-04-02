-module(opentelemetry_prometheus).

-export([collect_mf/2,
         deregister_cleanup/1]).

-export([export/1]).

-behaviour(prometheus_collector).

collect_mf(_Registry, Callback) ->
    export(Callback),
    ok.

deregister_cleanup(_Registry) ->
    ok.

export(Callback) ->
    ot_metric_accumulator:collect(),
    Records = ot_metric_integrator:read(),
    maps:fold(fun({Name, LabelSet}, Record, Acc) ->
                      [Callback(view_data_to_mf(atom_to_binary(Name, utf8), LabelSet, Record)) | Acc]
              end, [], Records).

view_data_to_mf(Name, Tags, #{description := Description,
                              aggregator := Aggregator,
                              value := Value}) ->
    FullRows = [{Tags, Value}],
    Metrics = rows_to_metrics(Aggregator, FullRows),
    prometheus_model_helpers:create_mf(sanitize(Name), Description, to_prom_type(Aggregator), Metrics).

rows_to_metrics(ot_metric_aggregator_last_value, [{Tags, {Value, _Time}}]) ->
    prometheus_model_helpers:gauge_metrics([{Tags, Value}]);
rows_to_metrics(ot_metric_aggregator_sum, Rows) ->
    prometheus_model_helpers:counter_metrics(Rows);
rows_to_metrics(ot_metric_aggregator_mmsc, [{Tags, {Min, Max, Sum, Count}}]) ->
    prometheus_model_helpers:histogram_metric(
      Tags, [{0, Min}, {1, Max}], Count, Sum).

to_prom_type(ot_metric_aggregator_last_value) ->
    gauge;
to_prom_type(ot_metric_aggregator_sum) ->
    counter;
to_prom_type(ot_metric_aggregator_mmsc) ->
    summary.

%% replace all non-alphanumeric characters with underscores
sanitize(String) ->
    case re:replace(String, "[^[:alpha:][:digit:]:]+", "_", [global]) of
        [$_ | _]=S ->
            ["key", S];
        [D | _]=S when D >= 48 andalso D =< 57->
            ["key_", S];
        S ->
            S
    end.
