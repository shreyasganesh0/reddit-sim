import gleam/result
import gleam/bytes_tree
import gleam/bit_array

import gleam/http/response
import gleam/http/request

import gleam/otp/actor
import gleam/erlang/process

import gleam/dynamic
import gleam/dynamic/decode

import mist

import utls

import generated/generated_types as gen_types
import generated/generated_decoders as gen_decode


type SSEState {

    SSEState(
        self_sub: process.Subject(SSEMessage),
        engine_pid: process.Pid,
        self_selector: process.Selector(gen_types.UserMessage),
        user_id: String
    )
}

type SSEMessage {

    DmStarted(dm: gen_types.Dm)

    DmReplied(dm: gen_types.Dm)
}


@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn register_notifications(
    req: request.Request(mist.Connection),
    engine_pid: process.Pid,
    self_selector: process.Selector(gen_types.UserMessage),
    ) -> response.Response(mist.ResponseData) {

    {
    use user_id <- result.try(
        result.map_error(
            request.get_header(req, "authorization"),
            fn(_) {

                response.new(401)
                |>response.set_body(
                    bytes_tree.new()
                    |>bytes_tree.append(bit_array.from_string("Unauthorized"))
                )
            }
        )
    )
    let def_resp = response.new(200)|>response.set_body(
                    bytes_tree.new()
                    |>bytes_tree.append(bit_array.from_string("Invalid input too long"))
                )
    Ok(mist.server_sent_events(
        req,
        def_resp,
        fn(sub) {notification_init(sub, engine_pid, self_selector, user_id)},
        handle_notifications
    ))
    }
    |> result.unwrap(response.new(404)|>response.set_body(mist.Bytes(bytes_tree.new())))
        
}

fn notification_init(
    sub: process.Subject(SSEMessage),
    engine_pid: process.Pid,
    self_selector: process.Selector(gen_types.UserMessage),
    user_id: String
    ) -> Result(actor.Initialised(SSEState, SSEMessage, process.Subject(SSEMessage)), String) {

    let init_state = SSEState(
        self_sub: sub,
        engine_pid: engine_pid,
        self_selector: self_selector,
        user_id: user_id
    )


    let selector = process.new_selector() 
    let selector_tag_list = get_sse_selector_list()

    let selector = utls.create_selector(selector, selector_tag_list)
    |> process.select_map(sub, fn(msg) {msg})

    utls.send_to_pid(engine_pid, #("register_notification", self(), user_id))

    let res = actor.initialised(init_state)
    |> actor.returning(sub)
    |> actor.selecting(selector)

    Ok(res)
}

fn handle_notifications(
    state: SSEState,
    msg: SSEMessage,
    _conn: mist.SSEConnection
    ) -> actor.Next(SSEState, SSEMessage) {

    case msg {

        DmStarted(_dm) -> {

            actor.continue(state)
        }

        DmReplied(_dm) -> {

            actor.continue(state)
        }
    }
}

fn replied_selector(
	data: dynamic.Dynamic
	) -> SSEMessage {

	let res = {

		use dm <- result.try(decode.run(data, decode.at([1], gen_decode.dm_decoder())))
		Ok(dm)
	}

	case res {

		Ok(dm) -> {

            DmReplied(dm)
		}

		Error(_) -> {

			panic as "Failed to parse dm started"
		}
	}
}

fn started_selector(
	data: dynamic.Dynamic
	) -> SSEMessage {

	let res = {

		use dm <- result.try(decode.run(data, decode.at([1], gen_decode.dm_decoder())))
		Ok(dm)
	}

	case res {

		Ok(dm) -> {

            DmStarted(dm)
		}

		Error(_) -> {

			panic as "Failed to parse dm started"
		}
	}
}

fn get_sse_selector_list() {

    [
    #("dm_started", started_selector, 1),
    #("dm_replied", replied_selector, 1)
    ]
}
