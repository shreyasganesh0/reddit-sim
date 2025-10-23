import gleam/io
import gleam/dict
import gleam/result
import gleam/crypto
import gleam/bit_array
import gleam/option.{Some, None}
import gleam/dynamic

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision 

import gleam/erlang/process
import gleam/erlang/atom

import youid/uuid

import types 
import selectors
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
                        user_metadata: dict.new(),
                        pidmap: dict.new(),
                        subreddit_metadata: dict.new(),
                        topicmap: dict.new(),
                        user_index: dict.new(),
                        subreddit_index: dict.new(),
                        subreddit_posts: dict.new(),
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
    let selector_tag_list = get_selector_list()

    let selector = utls.create_selector(selector, selector_tag_list)

    let ret = actor.initialised(init_state)
    |> actor.returning(types.EngineTestMessage)
    |> actor.selecting(selector)

    Ok(ret)
}

fn get_selector_list() -> List(#(String, fn(dynamic.Dynamic) -> types.EngineMessage, Int)) {

        [
        #("register_user", selectors.register_user_selector, 3),
        #("create_subreddit", selectors.create_subreddit_selector, 3),
        #("join_subreddit", selectors.join_subreddit_selector, 3),
        #("create_post", selectors.create_post_selector, 4)
        ]
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

            case dict.has_key(state.user_metadata, username) {

                True -> {

                    utls.send_to_pid(send_pid, #("register_user_failed"))
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
                                        user_metadata: dict.insert(
                                                    state.user_metadata,
                                                    uid,
                                                    types.UserMetaData(
                                                        username, passhash, []
                                                    ),
                                                 ),
                                        pidmap: dict.insert(
                                                    state.pidmap,
                                                    uid,
                                                    send_pid,
                                                ),
                                        user_index: dict.insert(
                                                        state.user_index,
                                                        username,
                                                        uid
                                                    )
                                    )
                    utls.send_to_pid(send_pid, #("register_user_success", uid))
                    actor.continue(new_state)
                }
            }
        }


        types.CreateSubReddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use _ <- result.try(utls.validate_request(send_pid, uuid, state.pidmap, state.user_metadata))
                case dict.has_key(state.subreddit_index, subreddit_name) {

                    False -> {

                        Ok(Nil)
                    }
                    
                    True -> {

                        let fail_reason = "Subreddit already exists"
                        Error(fail_reason)
                    }
                }
            }

            let new_state = case res {

                Ok(_) -> {

                    let subreddit_uuid = uuid.v4_string()
                    let new_state = types.EngineState(
                                        ..state,
                                        subreddit_metadata: dict.insert(
                                            state.subreddit_metadata,
                                            subreddit_uuid,
                                            types.SubRedditMetaData(
                                                name: subreddit_name,
                                                creator_id: uuid 
                                            ),
                                        ),
                                        subreddit_index: dict.insert(
                                            state.subreddit_index,
                                            subreddit_name,
                                            subreddit_uuid,
                                        )
                                    )
                    utls.send_to_pid(send_pid, #("create_subreddit_success", subreddit_name))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_subreddit_failed", subreddit_name, reason))
                    state
                }
            }

            actor.continue(new_state)
        }

        types.JoinSubReddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use username <- result.try(utls.validate_request(send_pid, uuid, state.pidmap, state.user_metadata))
                use subreddit_uuid <- result.try(
                                        result.map_error(
                                            dict.get(state.subreddit_index, subreddit_name),
                                            fn(_) {"Subreddit does not exist"}
                                        )
                                    )
                Ok(#(username, subreddit_uuid))
            }

            let new_state = case res {

                Ok(#(username, subreddituuid)) -> {

                    io.println("[ENGINE]: username: " <> username <> "joining subreddit: " <> subreddituuid)
                    let new_state = types.EngineState(
                        ..state,
                        topicmap: dict.upsert(
                                    state.topicmap, 
                                    subreddituuid,
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
                                  ),
                        user_metadata: dict.upsert(
                                        state.user_metadata,
                                        uuid,
                                        fn(maybe_user) {

                                            case maybe_user {

                                                None -> panic as "shouldnt be possible for user not to exist while joining"

                                                Some(types.UserMetaData(
                                                        username, pass, subreddit_list
                                                    )) -> {

                                                    types.UserMetaData(
                                                        username,
                                                        pass,
                                                        [subreddituuid, ..subreddit_list]
                                                    )
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

        types.CreatePost(send_pid, uuid, subreddit_name, post_data) -> {

            let res = {
                use username <- result.try(utls.validate_request(send_pid, uuid, state.pidmap, state.user_metadata))
                use subreddit_uuid <- result.try(
                                    result.map_error(
                                        dict.get(state.subreddit_index, subreddit_name),
                                        fn(_) {"Subreddit does not exist"}
                                    )
                                    )
                Ok(#(username, subreddit_uuid))
            }

            let new_state = case res {

                Ok(#(username, subreddit_uuid)) -> {

                    io.println("[ENGINE]: username: " <> username <> "creating post: " <> subreddit_uuid)
                    let new_state = types.EngineState(
                                        ..state,
                                        subreddit_posts: dict.upsert(
                                            state.subreddit_posts,
                                            subreddit_uuid,
                                            fn(maybe_posts) {

                                                case maybe_posts {

                                                    None -> {
                                                        [post_data]
                                                    }

                                                    Some(posts_list) -> {
                                                        [post_data, ..posts_list]
                                                    }
                                                }
                                            } 
                                        ),
                                    )
                    utls.send_to_pid(send_pid, #("create_post_success", subreddit_name))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_post_failed", subreddit_name, reason))
                    state
                }

            }

            actor.continue(new_state)
        }
    }
}
