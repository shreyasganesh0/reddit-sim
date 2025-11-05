import mist
import gleam/http
import gleam/http/request
import gleam/http/response

import gleam/erlang/process

import server/api_handlers

import generated/generated_types as gen_types

fn request_handler(
    req: request.Request(mist.Connection), 
    engine_sub: process.Subject(gen_types.EngineMessage)
    ) -> response.Response(mist.ResponseData) {
    

    case req.method, request.path_segments(req) {

        http.Post, ["echo"] -> {
                    
            api_handlers.echo_resp(req)

        }

        http.Post, ["api", "v1", ..rest] -> {

            case rest {

                ["register"] -> {

                    api_handlers.register_user(req, engine_sub)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        _, _ -> api_handlers.error_page_not_found()
    }
}



pub fn start(engine_sub: process.Subject(gen_types.EngineMessage)) {

    let assert Ok(_) = mist.new(fn(req) {request_handler(req, engine_sub)})
    |> mist.bind("localhost")
    |> mist.start
}
