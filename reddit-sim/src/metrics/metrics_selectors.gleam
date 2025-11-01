import gleam/dynamic/decode
import gleam/dynamic
import gleam/result


pub type MetricsMessage {
  
  RecordLatency(action: String, duration_ms: Int)

  RecordAction(action: String, status: String)

  RecordEngineStats(users: Int, posts: Int, comments: Int)

  PollEngine

  WriteToCsv
}

pub fn metrics_selector_list() {

    [
    #("engine_stats_reply", stats_selector, 3),
    #("record_latency", latency_selector, 2),
    #("record_action", outcome_selector, 2)
    ]
}

fn stats_selector(
	data: dynamic.Dynamic
	) -> MetricsMessage { 

	let res = {

		use users <- result.try(decode.run(data, decode.at([1], decode.int)))
		use post <- result.try(decode.run(data, decode.at([2], decode.int)))
		use comments <- result.try(decode.run(data, decode.at([3], decode.int)))
		Ok(#(users, post, comments))
	}

	case res {

		Ok(#(users, posts, comments)) -> {

              RecordEngineStats(users, posts, comments)
		}

		Error(_) -> {

			panic as "Failed to parse message record engine stats"
		}
	}
}
fn latency_selector(
	data: dynamic.Dynamic
	) -> MetricsMessage { 

	let res = {

		use msg_typ <- result.try(decode.run(data, decode.at([1], decode.string)))
		use latency <- result.try(decode.run(data, decode.at([2], decode.int)))
		Ok(#(msg_typ, latency))
	}

	case res {

		Ok(#(msg_typ, latency)) -> {

            RecordLatency(msg_typ, latency)
		}

		Error(_) -> {

			panic as "Failed to parse message record latency"
		}
	}
}

fn outcome_selector(
	data: dynamic.Dynamic
	) -> MetricsMessage { 

	let res = {

		use msg_typ <- result.try(decode.run(data, decode.at([1], decode.string)))
		use outcome <- result.try(decode.run(data, decode.at([2], decode.string)))
		Ok(#(msg_typ, outcome))
	}

	case res {

		Ok(#(msg_typ, outcome)) -> {

            RecordAction(msg_typ, outcome)
		}

		Error(_) -> {

			panic as "Failed to parse message record outcome"
		}
	}
}
