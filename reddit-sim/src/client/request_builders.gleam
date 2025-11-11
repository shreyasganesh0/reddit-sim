import gleam/http/request
import gleam/json
import gleam/function
import gleam/http
import gleam/int
import gleam/dict
import gleam/result
import gleam/bit_array

pub fn register_user(username: String, password: String) {

    let send_body = dict.from_list([#("username", username), #("password", password)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/register")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_body(send_body)
    |> request.set_method(http.Post)

}
