import mist
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/dict.{type Dict}
import gleam/result

import gleam/erlang/process

import server/api_handlers

import generated/generated_types as gen_types

fn request_handler(
    req: request.Request(mist.Connection), 
    engine_sub: process.Subject(gen_types.EngineMessage)
    ) -> response.Response(mist.ResponseData) {
    

    let endpoint = http.method_to_string(req.method) <> "-" <> req.path

    let api_func = path_handlers_list()
    |> dict.get(endpoint)
    |> result.unwrap(api_handlers.error_page_not_found)

    api_func(req, engine_sub)
}



pub fn start(engine_sub: process.Subject(gen_types.EngineMessage)) {

    let assert Ok(_) = mist.new(fn(req) {request_handler(req, engine_sub)})
    |> mist.bind("localhost")
    |> mist.start
}

fn path_handlers_list(
    ) -> Dict(
        String,
        fn(
            request.Request(mist.Connection),
            process.Subject(gen_types.EngineMessage)
        ) -> response.Response(mist.ResponseData)
        ) {

    [
    #("POST-/echo", api_handlers.echo_resp),
    #("POST-/api/v1/register", api_handlers.register_user),
    ]
    |>dict.from_list
}
