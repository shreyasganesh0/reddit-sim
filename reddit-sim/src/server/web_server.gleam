import mist
import gleam/http/request
import gleam/http/response

import gleam/erlang/process

import gleam/result
import gleam/bytes_tree

fn request_handler(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {
    
    let resp_404 = response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))

    case request.path_segments(req) {


        ["echo"] -> {

            echo_resp(req)
        }
        
        _ -> {

            resp_404
        }

        
    }
}

fn echo_resp(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {

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


pub fn main() {

    let assert Ok(_) = mist.new(request_handler)
    |> mist.bind("localhost")
    |> mist.start

    process.sleep_forever()
}
