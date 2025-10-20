import gleam/io
import gleam/dict
import gleam/result
import gleam/crypto
import gleam/bit_array
import gleam/option.{Some, None}
//import gleam/dynamic

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision 

import gleam/erlang/process
import gleam/erlang/atom

import youid/uuid

import types 
import utls

@external(erlang, "global", "register_name")
fn global_register(name: atom.Atom, pid: process.Pid) -> atom.Atom 


pub fn create() -> Nil {

    let main_sub = process.new_subject()
    let _ = supervisor.new(supervisor.OneForOne)
    |> supervisor.add(supervision.worker(fn() {start()}))
    |> supervisor.start

    process.receive_forever(main_sub)
    Nil
}

fn start() -> actor.StartResult(types.EngineMessage) {
    
    actor.new_with_initialiser(1000, fn(sub) {init(sub)})
    |> actor.on_message(handle_engine)
    |> actor.start
}

fn init(
    sub: process.Subject(types.EngineMessage),
    ) -> Result(actor.Initialised(types.EngineState, types.EngineMessage, types.EngineMessage), String) {

    let init_state = types.EngineState(
                        self_sub: sub,
                        usermap: dict.new(),
                        pidmap: dict.new(),
                        subredditmap: dict.new(),
                        topicmap: dict.new(),
                     )

    let engine_atom = atom.create("engine")
    let yes_atom = atom.create("yes")
    let assert Ok(pid) = process.subject_owner(sub)
    case engine_atom 
    |> global_register(pid) == yes_atom {

        True -> {

            io.println("successfully registered")
        }

        
        False -> {

            io.println("failed register of global name")
        }
        
    }

    let selector = process.new_selector() 
    let selector_tag_list = [
                            #("register_user", types.register_user_decoder, 3),
                            #("create_subreddit", types.create_subreddit_decoder, 3),
                            #("join_subreddit", types.join_subreddit_decoder, 3)
                            ]

    let selector = utls.create_selector(selector, selector_tag_list)

    let ret = actor.initialised(init_state)
    |> actor.returning(types.EngineTestMessage)
    |> actor.selecting(selector)

    Ok(ret)
}

fn handle_engine(
    state: types.EngineState,
    msg: types.EngineMessage,
    ) -> actor.Next(types.EngineState, types.EngineMessage) {

    case msg {

        types.EngineTestMessage -> {

            io.println("Started Engine...")
            actor.continue(state)
        }


        types.RegisterUser(send_pid, username, password) -> {

            io.println("[ENGINE]: recvd register user msg username: " <> username <> " password: "<> password)

            case dict.has_key(state.usermap, username) {

                True -> {

                    utls.send_to_pid(send_pid, #("register_failed"))
                    actor.continue(state)
                }

                False -> {

                    let uid = uuid.v4_string()

                    let passbits =  bit_array.from_string(password)
                    let passhash = crypto.new_hasher(crypto.Sha512)
                    |> crypto.hash_chunk(passbits)
                    |> crypto.digest

                    let new_state = types.EngineState(
                                        ..state,
                                        usermap: dict.insert(
                                                    state.usermap,
                                                    uid,
                                                    #(username, passhash),
                                                 ),
                                        pidmap: dict.insert(
                                                    state.pidmap,
                                                    uid,
                                                    send_pid,
                                                )
                                    )
                    utls.send_to_pid(send_pid, #("register_success", uid))
                    actor.continue(new_state)
                }
            }
        }


        types.CreateSubReddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use username <- result.try(utls.validate_request(send_pid, uuid, state.pidmap, state.usermap))
                case dict.has_key(state.subredditmap, subreddit_name) {

                    False -> {

                        Ok(username)
                    }
                    
                    True -> {

                        let fail_reason = "Subreddit already exists"
                        Error(fail_reason)
                    }
                }
            }

            let new_state = case res {

                Ok(username) -> {

                    let new_state = types.EngineState(
                                        ..state,
                                        subredditmap: dict.insert(
                                            state.subredditmap,
                                            subreddit_name,
                                            #(uuid, username)
                                        )
                                    )
                    utls.send_to_pid(send_pid, #("subreddit_create_success", subreddit_name))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("subreddit_create_failed", subreddit_name, reason))
                    state
                }
            }

            actor.continue(new_state)
        }

        types.JoinSubReddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use username <- result.try(utls.validate_request(send_pid, uuid, state.pidmap, state.usermap))
                use _ <- result.try(
                                        result.map_error(
                                            dict.get(state.subredditmap, subreddit_name),
                                            fn(_) {"Subreddit does not exist"}
                                        )
                                    )
                Ok(#(username, subreddit_name))
            }

            let new_state = case res {

                Ok(#(username, subredditname)) -> {

                    io.println("[ENGINE]: username: " <> username <> "joining subreddit: " <> subredditname)
                    let new_state = types.EngineState(
                        ..state,
                        topicmap: dict.upsert(
                                    state.topicmap, 
                                    subredditname,
                                    fn(maybe_list) {

                                        case maybe_list {

                                            Some(uuid_list) -> {

                                                [uuid, ..uuid_list]
                                            }

                                            None -> {

                                                [uuid]
                                            }
                                        }
                                    }
                                  )
                    )
                    utls.send_to_pid(send_pid, #("subreddit_join_success", subreddit_name))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("subreddit_join_failed", subreddit_name, reason))
                    state
                }
            }

            actor.continue(new_state)
        }
    }
}
