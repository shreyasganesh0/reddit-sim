import gleam/erlang/process
import gleam/dynamic
import gleam/list
import gleam/result
import gleam/dict.{type Dict}
import gleam/erlang/atom

import types

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
    sender_pid: process.Pid, 
    sender_uuid: String,
    pidmap: Dict(String, process.Pid), 
    usermap: Dict(String, types.UserMetaData)
    ) -> Result(String, String) {

        use pid <- result.try(
                    result.map_error(
                        dict.get(pidmap, sender_uuid),
                        fn(_) {

                            let fail_reason = "User was not registered" 
                            fail_reason
                        }
                    )
                   )
        use types.UserMetaData(username, _, _) <- result.try(
                                result.map_error(
                                    dict.get(usermap, sender_uuid),
                                    fn(_) {
                                        let fail_reason = 
                                            "UserId does not exist in username table"
                                        fail_reason
                                    }
                                )
                              )
        case pid == sender_pid {

            True -> {

                Ok(username)
            }

            False -> {

                let fail_reason = "Process did not match uuid"
                Error(fail_reason)
            }
        }
}

pub fn check_comment_parent(
    parent_id: String,
    posts_data: Dict(String, Post),
    comments_data: Dict(String, Comment)
    ) -> Result(Nil, Nil) {


    case dict.has_key(posts_data, parent_id) {

        True -> Ok(Nil)

        False -> {

            case dict.has_key(comments_data, parent_id) {

                True -> Ok(Nil)

                False -> {

                    let reason = "parent was not in posts or comments" 
                    Error(reason) 
                }
            }
        }
    }
}

