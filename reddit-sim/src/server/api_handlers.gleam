import mist
import gleam/http/request
import gleam/http/response

import gleam/erlang/process

import gleam/result
import gleam/bytes_tree
import gleam/bit_array

import gleam/json

import generated/generated_decoders as gen_decode

pub fn echo_resp(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {

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

pub fn register_user(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {

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
