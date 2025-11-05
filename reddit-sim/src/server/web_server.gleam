import mist
import gleam/http/request
import gleam/http/response

import gleam/erlang/process

import gleam/bytes_tree

import server/api_handlers

fn request_handler(req: request.Request(mist.Connection)) -> response.Response(mist.ResponseData) {
    
    let resp_404 = response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))

    case request.path_segments(req) {


        ["echo"] -> {

            api_handlers.echo_resp(req)
        }

        ["api", "v1", ..rest] -> {

            case rest {

                ["register"] -> {

                    api_handlers.register_user(req)

                }

                _ -> resp_404
            }
        }
        
        _ -> {

            resp_404
        }

        
    }
}



pub fn main() {

    let assert Ok(_) = mist.new(request_handler)
    |> mist.bind("localhost")
    |> mist.start

    process.sleep_forever()
}
