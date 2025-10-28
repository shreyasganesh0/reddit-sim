import gleam/io
import gleam/dict
import gleam/result
import gleam/crypto
import gleam/bit_array
import gleam/option.{Some, None}

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision 

import gleam/erlang/process
import gleam/erlang/atom

import youid/uuid

import generated/generated_types as gen_types 
import generated/generated_selectors as gen_select
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

fn start() -> actor.StartResult(process.Subject(gen_types.EngineMessage)) {
    
    actor.new_with_initialiser(1000, fn(sub) {init(sub)})
    |> actor.on_message(handle_engine)
    |> actor.start
}

fn init(
    sub: process.Subject(gen_types.EngineMessage),
    ) -> Result(actor.Initialised(gen_types.EngineState, gen_types.EngineMessage, process.Subject(gen_types.EngineMessage)), String) {

    let init_state = gen_types.EngineState(
                        self_sub: sub,
                        users_data: dict.new(),
                        user_pid_map: dict.new(),
                        subreddits_data: dict.new(),
                        subreddit_users_map: dict.new(),
                        user_rev_index: dict.new(),
                        subreddit_rev_index: dict.new(),
                        subreddit_posts_map: dict.new(),
                        posts_data: dict.new(),
                        comments_data: dict.new(),
                        parent_comment_map: dict.new(),
                        post_subreddit_map: dict.new(),
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
    let selector_tag_list = gen_select.get_engine_selector_list()

    let selector = utls.create_selector(selector, selector_tag_list)

    let ret = actor.initialised(init_state)
    |> actor.returning(sub)
    |> actor.selecting(selector)

    Ok(ret)
}

fn handle_engine(
    state: gen_types.EngineState,
    msg: gen_types.EngineMessage,
    ) -> actor.Next(gen_types.EngineState, gen_types.EngineMessage) {

    case msg {

//------------------------------------------------------------------------------------------------------
        gen_types.RegisterUser(send_pid, username, password) -> {

            io.println("[ENGINE]: recvd register user msg username: " <> username <> " password: "<> password)

            case dict.has_key(state.users_data, username) {

                True -> {

                    utls.send_to_pid(send_pid, #("register_user_failed", username, "username has been taken"))
                    actor.continue(state)
                }

                False -> {

                    let uid = uuid.v4_string()

                    let passbits =  bit_array.from_string(password)
                    let passhash = crypto.new_hasher(crypto.Sha512)
                    |> crypto.hash_chunk(passbits)
                    |> crypto.digest

                    let new_state = gen_types.EngineState(
                                        ..state,
                                        users_data: dict.insert(
                                                    state.users_data,
                                                    uid,
                                                    gen_types.User(
                                                        "", username, passhash, []
                                                    ),
                                                 ),
                                        user_pid_map: dict.insert(
                                                    state.user_pid_map,
                                                    uid,
                                                    send_pid,
                                                ),
                                        user_rev_index: dict.insert(
                                                        state.user_rev_index,
                                                        username,
                                                        uid
                                                    )
                                    )
                    utls.send_to_pid(send_pid, #("register_user_success", uid))
                    actor.continue(new_state)
                }
            }
        }


//------------------------------------------------------------------------------------------------------

        gen_types.CreateSubreddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use _ <- result.try(utls.validate_request(send_pid, uuid, state.user_pid_map, state.users_data))
                case dict.has_key(state.subreddit_rev_index, subreddit_name) {

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
                    let new_state = gen_types.EngineState(
                                        ..state,
                                        subreddits_data: dict.insert(
                                            state.subreddits_data,
                                            subreddit_uuid,
                                            gen_types.Subreddit(
                                                id: subreddit_uuid,
                                                name: subreddit_name,
                                                creator_id: uuid 
                                            ),
                                        ),
                                        subreddit_rev_index: dict.insert(
                                            state.subreddit_rev_index,
                                            subreddit_name,
                                            subreddit_uuid,
                                        )
                                    )
                    utls.send_to_pid(send_pid, #("create_subreddit_success", subreddit_uuid))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_subreddit_failed", subreddit_name, reason))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.JoinSubreddit(send_pid, uuid, subreddit_name) -> {

            let res = {
                use gen_types.User(username: username, ..) <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use subreddit_uuid <- result.try(
                                        result.map_error(
                                            dict.get(state.subreddit_rev_index, subreddit_name),
                                            fn(_) {"Subreddit does not exist"}
                                        )
                                    )
                Ok(#(username, subreddit_uuid))
            }

            let new_state = case res {

                Ok(#(username, subreddituuid)) -> {

                    io.println("[ENGINE]: username: " <> username <> "joining subreddit: " <> subreddituuid)
                    let new_state = gen_types.EngineState(
                        ..state,
                        subreddit_users_map: dict.upsert(
                                    state.subreddit_users_map, 
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
                        users_data: dict.upsert(
                                        state.users_data,
                                        uuid,
                                        fn(maybe_user) {

                                            case maybe_user {

                                                None -> panic as "shouldnt be possible for user not to exist while joining"

                                                Some(gen_types.User(
                                                        uuid, username, pass, subreddit_list
                                                    )) -> {

                                                    gen_types.User(
                                                        uuid,
                                                        username,
                                                        pass,
                                                        [subreddituuid, ..subreddit_list]
                                                    )
                                                }
                                            }
                                        }
                                       )
                    )
                    utls.send_to_pid(send_pid, #("join_subreddit_success", subreddituuid))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("join_subreddit_failed", subreddit_name, reason))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.CreatePost(send_pid, uuid, subreddit_id, post_data) -> {

            let res = {
                use _ <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use _subreddit_uuid <- result.try(
                                        result.map_error(
                                            dict.get(state.subreddits_data, subreddit_id),
                                            fn(_) {"Subreddit does not exist"}
                                        )
                                     )
                Ok(subreddit_id)
            }

            let new_state = case res {

                Ok(subreddit_uuid) -> {

                    let post_uuid = uuid.v4_string()
                    let post_data = gen_types.Post(
                                    ..post_data,
                                    id: post_uuid
                                  )
                    io.println("[ENGINE]: creating post: " <> subreddit_uuid)
                    let new_state = gen_types.EngineState(
                                        ..state,
                                        subreddit_posts_map: dict.upsert(
                                            state.subreddit_posts_map,
                                            subreddit_uuid,
                                            fn(maybe_posts) {

                                                case maybe_posts {

                                                    None -> {
                                                        [post_uuid]
                                                    }

                                                    Some(posts_list) -> {
                                                        [post_uuid, ..posts_list]
                                                    }
                                                }
                                            } 
                                        ),

                                        post_subreddit_map: dict.insert(
                                            state.post_subreddit_map,
                                            post_uuid,
                                            subreddit_uuid
                                        ),

                                        posts_data: dict.insert(
                                            state.posts_data,
                                            post_uuid,
                                            post_data
                                        )
                                    )
                    utls.send_to_pid(send_pid, #("create_post_success", post_uuid))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_post_failed", subreddit_id, reason))
                    state
                }

            }

            actor.continue(new_state)
        }


//------------------------------------------------------------------------------------------------------

        gen_types.CreateComment(send_pid, uuid, commentable_id, comment) -> {

            let res = {
                use _username <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use _exists <- result.try(
                                    utls.check_comment_parent(
                                        commentable_id,
                                        state.posts_data,
                                        state.comments_data,
                                    )
                                )
                Ok(Nil)
            }

            let new_state = case res {

                Ok(_) -> {

                    let comment_uuid = uuid.v4_string()
                    let comment = gen_types.Comment(
                                    ..comment,
                                    id:comment_uuid
                                  )
                    let new_state = gen_types.EngineState(
                        ..state,
                        parent_comment_map: dict.insert(
                            state.parent_comment_map,
                            commentable_id,
                            comment_uuid,
                        ),
                        comments_data: dict.insert(
                            state.comments_data,
                            comment_uuid,
                            comment
                        )
                    )
                    utls.send_to_pid(send_pid, #("create_comment_success", commentable_id)) 
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_comment_failed", commentable_id, reason))
                    state
                }
            }

            actor.continue(new_state)
        }
    }
}
