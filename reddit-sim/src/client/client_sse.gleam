import httpp/sse
import httpp/hackney
import gleam/http/request
import gleam/bytes_tree
import gleam/io

import gleam/otp/actor
import gleam/erlang/process

type ClientSSEState {

    ClientSSEState(
        self_sub: process.Subject(sse.SSEEvent),
        close_handler_sub: process.Subject(sse.SSEManagerMessage),
        mgr: hackney.ClientRef
    )
}

pub fn start(
    req: request.Request(bytes_tree.BytesTree),
    ) {

    actor.new_with_initialiser(10000, fn(sub) {init(sub, req)})
    |> actor.on_message(handle_client_sse)
    |> actor.start
}

fn init(
    sub: process.Subject(sse.SSEEvent),
    req: request.Request(bytes_tree.BytesTree),
    ) {

    case sse.event_source(req, 100000, sub) {

        Ok(#(mgr, close_handler_sub)) -> {

            io.println("[NOTIFICATION]: started sse_handler")
            let init_state = ClientSSEState(
                self_sub: sub,
                close_handler_sub: close_handler_sub,
                mgr: mgr
            )

            Ok(actor.initialised(init_state))
        }

        Error(_) -> {

            io.println("[NOTIFICATION]: failed start sse_handler")
            Error("failed to send sse")
        }
    }
}

fn handle_client_sse(
    state: ClientSSEState,
    msg: sse.SSEEvent
    ) {

    case msg {

        sse.Event(_event_type, _event_id, event) -> {

            case event {

                ": ping"<>_rest -> Nil

                _ -> io.println("[NOTIFICATION]: "<>event)
            }
            actor.continue(state)
        }

        sse.Closed -> {

            io.println("[NOTIFICATION]: recvd close")
            actor.stop()
        }
    }
}
