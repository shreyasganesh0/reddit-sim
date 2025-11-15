import gleam/erlang/process
import gleam/dynamic
import gleam/list
import gleam/result
import gleam/dict.{type Dict}
import gleam/erlang/atom
import gleam/json

import generated/generated_types as gen_types

@external(erlang, "gleam_stdlib", "identity")
pub fn unsafe_coerce(a: a) -> b

@external(erlang, "erlang", "send")
fn pid_send(pid: process.Pid, msg: dynamic.Dynamic) -> dynamic.Dynamic 

pub fn create_selector(
    selector: process.Selector(payload),
    selector_tags: List(#(String, fn(dynamic.Dynamic) -> payload, Int))
    ) -> process.Selector(payload) {


        list.fold(selector_tags, selector, fn(acc, a) {

                                               let #(tag, decoder, arity) = a
                                               process.select_record(acc, tag, arity, decoder)
                                           }
        )
}

@external(erlang, "global", "send")
fn global_send(name: atom.Atom, msg: dynamic.Dynamic) -> process.Pid 

pub fn send_to_engine(tup: a) -> process.Pid {
    case atom.get("engine") {

            Ok(engine_atom) -> {
                global_send(engine_atom, unsafe_coerce(tup)) 
            }

            Error(_) -> {

                panic as "[CLIENT]: failed to get engine atom in send"
            }
    }
}

pub fn send_to_pid(pid: process.Pid, tup: a) -> dynamic.Dynamic {

    pid_send(pid, unsafe_coerce(tup))
}

pub type ValidateError {

    ValidateError(fail_reason: String)
}

pub fn validate_request(
    _sender_pid: process.Pid, 
    sender_uuid: String,
    _pidmap: Dict(String, process.Pid), 
    usermap: Dict(String, gen_types.User)
    ) -> Result(gen_types.User, String) {

        use user <- result.try(
                        result.map_error(
                            dict.get(usermap, sender_uuid),
                            fn(_) {
                                let fail_reason = 
                                    "UserId does not exist in username table"
                                fail_reason
                            }
                        )
                      )
                Ok(user)
}

pub fn check_comment_parent(
    parent_id: String,
    posts_data: Dict(String, gen_types.Post),
    comments_data: Dict(String, gen_types.Comment)
    ) -> Result(#(String, gen_types.Commentable), String) {

    let def_post = gen_types.Post(
                id: "",
                title: "test title",
                body: "post_body",
                owner_id: "",
                upvotes: 0,
                downvotes: 0,
                subreddit_id: "",
               )
                
    let def_comment = gen_types.Comment(
                    id: "",
                    body: "comment_body",
                    parent_id: "",
                    owner_id: "",
                    upvotes: 0,
                    downvotes: 0,
                   )

    case dict.get(posts_data, parent_id) {

        Ok(post) -> Ok(#(
                        "post", 
                        gen_types.Commentable(
                            post: post,
                            comment: def_comment,
                        )
                        )
                    )

        Error(_) -> {

            case dict.get(comments_data, parent_id) {

                Ok(comment) -> Ok(#(
                                "comment",
                                gen_types.Commentable(
                                    post: def_post,
                                    comment: comment,
                                )
                                )
                               )

                Error(_) -> {

                    let reason = "parent was not in posts or comments" 
                    Error(reason) 
                }
            }
        }
    }
}

pub fn post_jsonify(post: gen_types.Post) {

        [
        #("id", json.string(post.id)),
        #("title", json.string(post.title)),
        #("body", json.string(post.body)),
        #("owner_id", json.string(post.owner_id)),
        #("upvotes", json.int(post.upvotes)),
        #("downvotes", json.int(post.downvotes)),
        #("subreddit_id", json.string(post.subreddit_id)),
        ]
    |> json.object
}

pub fn comment_jsonify(comment: gen_types.Comment) {

        [
        #("id", json.string(comment.id)),
        #("body", json.string(comment.body)),
        #("parent_id", json.string(comment.parent_id)),
        #("owner_id", json.string(comment.owner_id)),
        #("upvotes", json.int(comment.upvotes)),
        #("downvotes", json.int(comment.downvotes)),
        ]
        |> json.object
}
