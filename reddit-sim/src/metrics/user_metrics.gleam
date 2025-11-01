import gleam/dict.{type Dict}
import gleam/float

import gleam/erlang/process.{type Pid}

import gleam/time/timestamp
import gleam/time/duration

import youid/uuid

import utls

pub fn send_timing_metrics(
    req_id: String,
    msg_typ: String,
    pending_reqs: Dict(String, Float),
    metrics_pid: Pid
    ) -> Dict(String, Float) {

    let end = timestamp.system_time()
    let start = case dict.get(pending_reqs, req_id) {

        Ok(start) -> start |> float.round |> timestamp.from_unix_seconds

        Error(_) -> end
    }
    let latency_ms = {{timestamp.difference(end, start)|>duration.to_seconds} *. 1000.0} |> float.round
    utls.send_to_pid(
      metrics_pid, 
      #("record_latency", msg_typ, latency_ms)
    )
    utls.send_to_pid(
      metrics_pid, 
      #("record_action", msg_typ, "success")
    )
    
    dict.drop(pending_reqs, [req_id])
}

pub fn send_to_engine(
    pending_reqs: Dict(String, Float),
    ) -> #(String, Dict(String, Float)) {

    let req_id = uuid.v4_string()
    let start = timestamp.system_time()|> timestamp.to_unix_seconds
    #(req_id, dict.insert(pending_reqs, req_id, start))

}

