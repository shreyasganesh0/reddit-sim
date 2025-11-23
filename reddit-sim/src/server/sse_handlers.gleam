import gleam/result
import gleam/io
import gleam/bytes_tree
import gleam/string_tree
import gleam/string
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


type SSEState {

    SSEState(
        self_sub: process.Subject(SSEMessage),
        engine_pid: process.Pid,
        self_selector: process.Selector(gen_types.UserMessage),
        user_id: String
    )
}

type SSEMessage {

    DmStarted(dm: String)

    DmReplied(dm: String)

    PostCreated(post: String)

    CommentCreated(comment: String)

    Hearbeat
}


@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn register_notifications(
    req: request.Request(mist.Connection),
    engine_pid: process.Pid,
    self_selector: process.Selector(gen_types.UserMessage),
    ) -> response.Response(mist.ResponseData) {

    let down_selector = 
        process.ProcessDown(
            process.monitor(process.self()),
            process.self(),
            process.Normal
        )
    let selector = process.new_selector()
    |> process.select_monitors(
        fn(_down) {down_selector}
    )
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
    let def_resp = response.new(200)
                |> response.set_header("content-type", "text/event-stream")
                |> response.set_header("cache-control", "no-cache")
                |> response.set_header("connection", "keep-alive")
                |>response.set_body(mist.ServerSentEvents(selector))
    Ok(mist.server_sent_events(
        req,
        def_resp,
        fn(sub) {notification_init(sub, engine_pid, self_selector, user_id)},
        handle_notifications
    ))
    }
    |> result.unwrap(response.new(404)|>response.set_body(mist.ServerSentEvents(selector)))
        
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

    utls.send_to_pid(engine_pid, #("register_notifications", self(), user_id))
    process.send(sub, Hearbeat)

    let res = actor.initialised(init_state)
    |> actor.returning(sub)
    |> actor.selecting(selector)

    Ok(res)
}

fn handle_notifications(
    state: SSEState,
    msg: SSEMessage,
    conn: mist.SSEConnection
    ) -> actor.Next(SSEState, SSEMessage) {

    case msg {

        Hearbeat -> {

            let padding = string.repeat(" ", 1024)
            
            let _ = string_tree.from_string(": ping " <> padding <> "\n\n")
                |> mist.event
                |> mist.send_event(conn, _)

            process.send_after(state.self_sub, 2000, Hearbeat)
            actor.continue(state)
        }

        DmStarted(dm) -> {

            io.println("[SSE_SERVER]: got notification dm start: "<>dm)

            case string_tree.new()
            |> string_tree.prepend(dm)
            |> mist.event
            |> mist.send_event(conn, _) {

                Ok(_) -> {
                    io.println("[SSE_SERVER]: send event: "<>dm)
                }

                Error(_) -> {
                    io.println("[SSE_SERVER]: failed send event: "<>dm)
                }
            }
            actor.continue(state)
        }

        DmReplied(dm) -> {

            io.println("[SSE_SERVER]: got notification dm start: "<>dm)

            case string_tree.new()
            |> string_tree.prepend(dm)
            |> mist.event
            |> mist.send_event(conn, _) {

                Ok(_) -> {
                    io.println("[SSE_SERVER]: send event: "<>dm)
                }

                Error(_) -> {
                    io.println("[SSE_SERVER]: failed send event: "<>dm)
                }
            }
            actor.continue(state)
        }

        PostCreated(dm) -> {

            io.println("[SSE_SERVER]: got notification post created: "<>dm)

            case string_tree.new()
            |> string_tree.prepend(dm)
            |> mist.event
            |> mist.send_event(conn, _) {

                Ok(_) -> {
                    io.println("[SSE_SERVER]: send event: "<>dm)
                }

                Error(_) -> {
                    io.println("[SSE_SERVER]: failed send event: "<>dm)
                }
            }
            actor.continue(state)
        }

        CommentCreated(dm) -> {

            io.println("[SSE_SERVER]: got notification comment created: "<>dm)

            case string_tree.new()
            |> string_tree.prepend(dm)
            |> mist.event
            |> mist.send_event(conn, _) {

                Ok(_) -> {
                    io.println("[SSE_SERVER]: send event: "<>dm)
                }

                Error(_) -> {
                    io.println("[SSE_SERVER]: failed send event: "<>dm)
                }
            }
            actor.continue(state)
        }
    }
}

fn replied_selector(
	data: dynamic.Dynamic
	) -> SSEMessage {

	let res = {

		use dm <- result.try(decode.run(data, decode.at([1], decode.string)))
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

		use dm <- result.try(decode.run(data, decode.at([1], decode.string)))
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

fn post_created_selector(
	data: dynamic.Dynamic
	) -> SSEMessage {

	let res = {

		use post <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(post)
	}

	case res {

		Ok(post) -> {

            PostCreated(post)
		}

		Error(_) -> {

			panic as "Failed to parse post created"
		}
	}
}

fn comment_created_selector(
	data: dynamic.Dynamic
	) -> SSEMessage {

	let res = {

		use comment <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(comment)
	}

	case res {

		Ok(comment) -> {

            CommentCreated(comment)
		}

		Error(_) -> {

			panic as "Failed to parse comment created"
		}
	}
}

fn get_sse_selector_list() {

    [
    #("dm_started", started_selector, 1),
    #("dm_replied", replied_selector, 1),
    #("post_created", post_created_selector, 1),
    #("comment_created", comment_created_selector, 1)
    ]
}
