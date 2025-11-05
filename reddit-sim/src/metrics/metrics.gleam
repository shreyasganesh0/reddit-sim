import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/string
import gleam/option.{Some, None}
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode

import gleam/otp/actor

import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/atom
import gleam/erlang/node

import gleam/time/timestamp
import gleam/time/duration
import simplifile

//import generated/generated_types as gen_types
import generated/generated_decoders as gen_decode

import utls
import metrics/metrics_selectors as met_sel

pub type MetricsState {

  MetricsState(
    self_sub: Subject(met_sel.MetricsMessage),
    main_sub: Subject(Nil),
    latencies: Dict(String, List(Int)),
    action_counts: Dict(String, Int),
    engine_stats: Dict(String, Int),
    engine_pid: Pid,
    start_time: timestamp.Timestamp,
    shutdown_count: Int,
    num_users: Int,
  )
}

@external(erlang, "global", "register_name")
fn global_register(name: atom.Atom, pid: Pid) -> atom.Atom

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic

@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn create(num_users: Int) -> Nil {
    let main_sub = process.new_subject()
    let _ = start(num_users, main_sub)
    process.receive_forever(main_sub)
    Nil
}


fn start(num_users: Int, main_sub) -> actor.StartResult(Subject(met_sel.MetricsMessage)) {
    
    actor.new_with_initialiser(1000, fn(sub) {init(sub, main_sub, num_users)})
    |> actor.on_message(handle_metrics)
    |> actor.start
}

fn init(
    sub: Subject(met_sel.MetricsMessage),
    main_sub: Subject(Nil),
    num_users: Int
    ) -> Result(
            actor.Initialised(
                MetricsState,
                met_sel.MetricsMessage,
                Subject(met_sel.MetricsMessage)
            ),
           String 
        ) {

        let metrics_atom = atom.create("metrics")
        let engine_atom = atom.create("engine")
        let yes_atom = atom.create("yes")

        let engine_node = atom.create("engine@localhost")

        let assert Ok(pid) = process.subject_owner(sub)
        case metrics_atom 
        |> global_register(pid) == yes_atom {

            True -> {

                io.println("successfully registered")
            }

            
            False -> {

                io.println("failed register of global name")
            }
            
        }

        case node.connect(engine_node) {
            
            Ok(_node) -> {

                io.println("Connected to engine")
            }

            Error(err) -> {

                case err {

                    node.FailedToConnect -> io.println("Node failed to connect")

                    node.LocalNodeIsNotAlive -> io.println("Not in distributed mode")
                }
            }

        }


        process.sleep(500)
        let data = global_whereisname(engine_atom)
        let pid = case decode.run(data, gen_decode.pid_decoder()) {

            Ok(engine_pid) -> {

                io.println("Found engine's pid")
                engine_pid
            }

            Error(_) -> {

                io.println("Couldnt find engine's pid")
                panic
            }
        }

        let init_state = MetricsState(
            self_sub: sub,
            main_sub: main_sub,
            latencies: dict.new(),
            action_counts: dict.new(),
            engine_stats: dict.new(),
            engine_pid: pid,
            start_time: timestamp.system_time(),
            shutdown_count: 0,
            num_users: num_users,
        )

        process.send_after(sub, 5000, met_sel.PollEngine)
        process.send_after(sub, 10000, met_sel.WriteToCsv)

        let selector_tag_list = met_sel.metrics_selector_list()
        let selector = 
        process.new_selector()
        |> utls.create_selector(selector_tag_list)
        |> process.select_map(sub, fn(msg) {msg})
        Ok(
            actor.initialised(init_state)
            |> actor.returning(sub)
            |> actor.selecting(selector),
        )
}



fn handle_metrics(
    state: MetricsState,
    msg: met_sel.MetricsMessage,
    ) -> actor.Next(MetricsState, met_sel.MetricsMessage) {

    case msg {

        met_sel.ShutdownUser -> {

            let count = state.shutdown_count + 1
            io.println("[METRICS]: recvd shutdown from user")
            case count < state.num_users {

                True -> {

                    let state = MetricsState(
                        ..state,
                        shutdown_count: count,
                    )
                    actor.continue(state)
                }

                False ->{

                    write_csv(state)
                    process.send(state.main_sub, Nil)
                    actor.stop()
                }
            }
        }

        met_sel.RecordLatency(action, duration_ms) -> {

            let new_latencies = dict.upsert(
                state.latencies,
                action,
                fn(maybe_list) {

                    case maybe_list {

                        Some(list) -> [duration_ms, ..list]

                        None -> [duration_ms]
                    }
                }
            )

            actor.continue(MetricsState(..state, latencies: new_latencies))
        }

        met_sel.RecordAction(action, status) -> {

            let key = action <> "_" <> status
            let new_counts = dict.upsert(
                state.action_counts,
                key, 
                fn(maybe_count) {
                    case maybe_count {

                        Some(count) -> count + 1
                        
                        None -> 1
                    }
                }
            )

            actor.continue(MetricsState(..state, action_counts: new_counts))
        }

        met_sel.PollEngine -> {

            utls.send_to_pid(state.engine_pid, #("metrics_enginestats", self()))
            process.send_after(state.self_sub, 5_000, met_sel.PollEngine)
            actor.continue(state)
        }

        met_sel.RecordEngineStats(users, posts, comments) -> {

            io.println("[METRICS]: logging engine stats users: " <> int.to_string(users) <>", posts: "<>int.to_string(posts)<> ", comments: "<>int.to_string(comments))
            let new_stats = state.engine_stats
            |> dict.insert("total_users", users)
            |> dict.insert("total_posts", posts)
            |> dict.insert("total_comments", comments)
            actor.continue(MetricsState(..state, engine_stats: new_stats))
        }

        met_sel.WriteToCsv -> {

            io.println("[METRICS]: writing to csv")

            write_csv(state)
            process.send_after(state.self_sub, 10_000, met_sel.WriteToCsv)
            actor.continue(MetricsState(..state, latencies: dict.new()))
        }
    }
}

fn write_csv(state: MetricsState) -> Nil {

    let elapsed_seconds = timestamp.difference(state.start_time, timestamp.system_time()) 
    |> duration.to_seconds
    |> float.round

    let latency_lines =
    dict.to_list(state.latencies)
    |> list.map(fn(item) {

                let #(action, times) = item
                let count = list.length(times)
                let sum = list.fold(times, 0, fn(a, b) { a + b })
                let avg = case count {
                    
                    0 -> 0

                    _ -> sum / count
                  }
                [
                    int.to_string(elapsed_seconds),
                    "latency_avg_ms",
                    action,
                    int.to_string(avg),
                ]
                |> string.join(",")
              }
       )

    let health_lines =
    dict.to_list(state.action_counts)
    |> list.map(fn(item) {

                let #(action_status, count) = item
                [
                    int.to_string(elapsed_seconds),
                    "health_count",
                    action_status,
                    int.to_string(count),
                ]
                |> string.join(",")
            }
        )

    let engine_lines =
    dict.to_list(state.engine_stats)
    |> list.map(fn(item) {
                  let #(stat_name, value) = item
                  [
                    int.to_string(elapsed_seconds),
                    "engine_stat",
                    stat_name,
                    int.to_string(value),
                  ]
                  |> string.join(",")
                }
    )

    let all_lines =
        list.append(latency_lines, health_lines)|>list.append(engine_lines)
        |> string.join("\n")

    case all_lines == "\n" {

        True -> Nil

        False -> {

            case simplifile.append("metrics.csv", all_lines <> "\n") {

                Ok(_) -> Nil
                
                Error(e) -> io.println_error("Failed to write CSV: " <> simplifile.describe_error(e))
            }
        }
    }

}
