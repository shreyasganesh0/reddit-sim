import gleam/http/request
import gleam/json
import gleam/function
import gleam/http
import gleam/int
import gleam/dict
import gleam/result
import gleam/bit_array

import generated/generated_types as gen_types

import utls

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

pub fn login_user(username: String, password: String) {

    let send_body = dict.from_list([#("username", username), #("password", password)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/login")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn create_subreddit(subreddit_name: String, user_id: String) {

    let send_body = dict.from_list([#("subreddit_name", subreddit_name)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/subreddit")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn join_subreddit(subreddit_name: String, subreddit_id: String, user_id: String) {

    let send_body = dict.from_list([#("subreddit_id", subreddit_id)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/r/"<>subreddit_name<>"/api/subscribe")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn leave_subreddit(subreddit_name: String, subreddit_id: String, user_id: String) {

    let send_body = dict.from_list([#("subreddit_id", subreddit_id)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/r/"<>subreddit_name<>"/api/subscribe")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Delete)
}

pub fn search_subreddit(subreddit_name: String, user_id: String) {

    let base_req = request.to("http://localhost:4000/api/v1/search_subreddit?q="<>subreddit_name)
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("authorization", user_id)
    |> request.set_method(http.Get)
}

pub fn create_post(
    subreddit_name: String,
    subreddit_id: String,
    user_id: String,
    title: String,
    body: String) {

    let post_body =
        gen_types.Post(
        id: "",
        title: title,
        body: body,
        owner_id: "",
        subreddit_id: subreddit_id,
        upvotes: 0,
        downvotes: 0
    )
    |> utls.post_jsonify

    let send_body = json.object([#("subreddit_id", json.string(subreddit_id)), #("post", post_body)])
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/r/"<>subreddit_name<>"/api/submit")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn create_repost(post_id: String, user_id: String) {

    let send_body = dict.from_list([#("post_id", post_id)])
    |> json.dict(function.identity, json.string)
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/repost")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn get_post(post_id: String, user_id: String) {


    let base_req = request.to("http://localhost:4000/api/v1/post/"<>post_id)
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("authorization", user_id)
    |> request.set_method(http.Get)
}

pub fn delete_post(post_id: String, user_id: String) {

    let base_req = request.to("http://localhost:4000/api/v1/post/"<>post_id)
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("authorization", user_id)
    |> request.set_method(http.Delete)
}

pub fn create_comment(parent_id: String, user_id: String, body: String) {

    let comment_body =
        gen_types.Comment(
        id: "",
        parent_id: "",
        body: body,
        owner_id: "",
        upvotes: 0,
        downvotes: 0
    )
    |> utls.comment_jsonify

    let send_body = json.object([#("commentable_id", json.string(parent_id)), #("comment", comment_body)])
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/comment")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}

pub fn create_vote(parent_id: String, user_id: String, vote_t: String) {

    let send_body = json.object(
        [
        #("commentable_id", json.string(parent_id)),
        #("vote_type", json.string(vote_t))
        ]
    )
    |> json.to_string
    |> bit_array.from_string

    let content_length = bit_array.byte_size(send_body)
    let base_req = request.to("http://localhost:4000/api/v1/vote")
    |> result.unwrap(request.new())
    |> request.map(bit_array.from_string)
    
    base_req
    |> request.set_header("Content-Length", int.to_string(content_length))
    |> request.set_header("authorization", user_id)
    |> request.set_body(send_body)
    |> request.set_method(http.Post)
}
