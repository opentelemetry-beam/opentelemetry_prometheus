-module(opentelemetry_prometheus_SUITE).

-compile(export_all).

-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

-include_lib("opentelemetry_api/include/opentelemetry.hrl").
-include_lib("opentelemetry_api/include/meter.hrl").

all() ->
    [counter].

init_per_suite(Config) ->
    application:load(prometheus),
    application:set_env(prometheus, collectors, []),
    {ok, _} = application:ensure_all_started(opentelemetry_prometheus),
    prometheus_registry:register_collector(opentelemetry_prometheus),
    Config.

end_per_suite(_Config) ->
    _ = application:stop(opentelemetry_prometheus),
    ok.

counter(_Config) ->
    ?assertMatch({ot_meter_default, _}, ?current_meter),

    ?new_instruments([#{name => mycounter,
                        kind => counter,
                        description => <<"helllo description 1">>,
                        input_type => integer,
                        label_keys => ["a"]}]),
    ?new_instruments([#{name => myfloat,
                        kind => counter,
                        description => <<"helllo description 2">>,
                        input_type => float,
                        label_keys => ["a"]}]),
    ?counter_add(mycounter, 4, []),
    ?counter_add(mycounter, 5, []),

    ?counter_add(myfloat, 4.1, []),
    ?counter_add(myfloat, 5.1, []),

    ot_meter_default:new_instruments([], [#{name => myobserver,
                                            kind => observer,
                                            input_type => integer,
                                            label_keys => ["a"]}]),

    ot_meter_default:register_observer(meter, myobserver, fun(R) ->
                                                                  ot_observer:observe(R, 3, [{"a", "b"}]),
                                                                  ok
                                                          end),

    ot_meter_default:new_instruments([], [#{name => m1,
                                            kind => measure,
                                            input_type => integer,
                                            label_keys => [key1]}]),

    ot_meter_default:record(meter, m1, [{key1, value1}], 2),
    ot_meter_default:record(meter, m1, [{key1, value2}], 8),
    ot_meter_default:record(meter, m1, [{key1, value1}], 5),

    ?assertEqual(expected(), prometheus_text_format:format()),

    ok.

expected() ->
    <<"# TYPE m1 summary
# HELP m1 \nm1_bucket{key1=\"value1\",le=\"0\"} 2
m1_bucket{key1=\"value1\",le=\"1\"} 5
m1_count{key1=\"value1\"} 2
m1_sum{key1=\"value1\"} 7
# TYPE m1 summary
# HELP m1 \nm1_bucket{key1=\"value2\",le=\"0\"} 8
m1_bucket{key1=\"value2\",le=\"1\"} 8
m1_count{key1=\"value2\"} 1
m1_sum{key1=\"value2\"} 8
# TYPE mycounter counter
# HELP mycounter helllo description 1
mycounter 9
# TYPE myfloat counter
# HELP myfloat helllo description 2
myfloat 9.2
# TYPE myobserver gauge
# HELP myobserver \nmyobserver{a=\"b\"} 3\n\n">>.
