import mist
import gleam/http/request
import gleam/http/response

import gleam/erlang/process

import gleam/result
import gleam/bytes_tree
import gleam/bit_array

import gleam/json
import gleam/io

import generated/generated_decoders as gen_decode
import generated/generated_types as gen_types

pub fn echo_resp(
    req: request.Request(mist.Connection),
    _engine_sub: process.Subject(gen_types.EngineMessage),
    ) -> response.Response(mist.ResponseData) {

    io.println("[SERVER]: recvd echo request")

    let content_type = request.get_header(req, "content-type")
    |> result.unwrap("plain/text")

    mist.read_body(req, 1024) 
    |> result.map(
        fn(a) {

            response.new(200)
            |> response.set_body(mist.Bytes(bytes_tree.new()|>bytes_tree.append(a.body)))
            |> response.set_header("content-type", content_type)
        }
    )
    |> result.lazy_unwrap(fn() {response.new(404)
        |>response.set_body(mist.Bytes(bytes_tree.new()))})
}

pub fn register_user(
    req: request.Request(mist.Connection),
    engine_sub: process.Subject(gen_types.EngineMessage),
    ) -> response.Response(mist.ResponseData) {

    io.println("[SERVER]: recvd register request")

    let content_type = request.get_header(req, "content-type")
    |> result.unwrap("plain/text")

    mist.read_body(req, 1024) 
    |> result.map(
        fn(a) {

            let user_details = a.body
            |> json.parse_bits(gen_decode.rest_register_user_decoder())
            
            echo user_details

            response.new(200)
            |> response.set_body(
                mist.Bytes(
                    bytes_tree.new()
                    |>bytes_tree.append(
                        bit_array.from_string("test")
                    )
                )
            )
            |> response.set_header("content-type", content_type)
        }
    )
    |> result.lazy_unwrap(fn() {response.new(404)
    |>response.set_body(mist.Bytes(bytes_tree.new()))})
}

pub fn error_page_not_found(
    _req: request.Request(mist.Connection),
    _engine_sub: process.Subject(gen_types.EngineMessage),
    ) -> response.Response(mist.ResponseData) {

    io.println("[SERVER]: recvd invalid request")
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))
}
