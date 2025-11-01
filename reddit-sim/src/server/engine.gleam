import gleam/io
import gleam/dict.{type Dict}
import gleam/list.{Continue, Stop}
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
import generated/generated_decoders as gen_decoders
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
                        dms_data: dict.new(),
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

        gen_types.MetricsEnginestats(send_pid) -> {

            io.println("[ENGINE]: recvd get stats req")
            let users = dict.size(state.users_data)
            let posts = dict.size(state.posts_data)
            let comments = dict.size(state.comments_data)

            utls.send_to_pid(
              send_pid,
              #("engine_stats_reply", users, posts, comments)
            )
            actor.continue(state)
        }
//------------------------------------------------------------------------------------------------------
        gen_types.RegisterUser(send_pid, username, password, req_id) -> {

            io.println("[ENGINE]: recvd register user msg username: " <> username <> " password: "<> password)

            case dict.has_key(state.users_data, username) {

                True -> {

                    utls.send_to_pid(send_pid, #("register_user_failed", username, "username has been taken", req_id))
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
                                                        id: uid, 
                                                        username: username,
                                                        passhash: passhash,
                                                        subreddits_membership_list: [],
                                                        post_karma: 0,
                                                        comment_karma: 0,
                                                        dms_list: [],
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
                    utls.send_to_pid(send_pid, #("register_user_success", uid, req_id))
                    actor.continue(new_state)
                }
            }
        }


//------------------------------------------------------------------------------------------------------

        gen_types.CreateSubreddit(send_pid, uuid, subreddit_name, req_id) -> {

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
                    io.println("[ENGINE]: created subreddit: " <> subreddit_uuid)
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
                    utls.send_to_pid(send_pid, #("create_subreddit_success", subreddit_uuid, req_id))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_subreddit_failed", subreddit_name, reason, req_id))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.JoinSubreddit(send_pid, uuid, subreddit_id, req_id) -> {

            let res = {
                use gen_types.User(username: username, ..) <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use _subreddit <- result.try(
                                        result.map_error(
                                            dict.get(state.subreddits_data, subreddit_id),
                                            fn(_) {"Subreddit does not exist"}
                                        )
                                    )
                Ok(#(username, subreddit_id))
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

                                                Some(user) -> {

                                                    gen_types.User(
                                                        ..user,
                                                        subreddits_membership_list:
                                                        [subreddituuid, ..user.subreddits_membership_list]
                                                    )
                                                }
                                            }
                                        }
                                       )
                    )
                    utls.send_to_pid(send_pid, #("join_subreddit_success", subreddit_id, req_id))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("join_subreddit_failed", subreddit_id, reason, req_id))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.CreateRepost(send_pid, uuid, post_id, req_id) -> {

            let res = {
                use user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use post <- result.try(
                                        result.map_error(
                                            dict.get(state.posts_data, post_id),
                                            fn(_) {"post does not exist"}
                                        )
                                     )
                Ok(#(user, post))
            }

            let new_state = case res {

                Ok(#(user, post_data)) -> {

                    let post_uuid = uuid.v4_string()
                    let post_data = gen_types.Post(
                                    ..post_data,
                                    owner_id: user.id,
                                    id: post_uuid
                                  )

                    case dict.get(state.subreddits_data, post_data.subreddit_id) {

                        Ok(_) -> {

                            io.println("[ENGINE]: creating repost: " <> post_uuid)
                            let new_state = gen_types.EngineState(
                                                ..state,
                                                subreddit_posts_map: dict.upsert(
                                                    state.subreddit_posts_map,
                                                    post_data.subreddit_id,
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
                                                    post_data.subreddit_id
                                                ),

                                                posts_data: dict.insert(
                                                    state.posts_data,
                                                    post_uuid,
                                                    post_data
                                                )
                                            )
                            utls.send_to_pid(send_pid, #("create_repost_success", post_uuid, req_id))
                            new_state
                        }

                        Error(_) -> {

                            let reason = "post was in a invalid state"
                            utls.send_to_pid(send_pid, #("create_repost_failed", post_id, reason, req_id))
                            state
                        }
                    }
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_repost_failed", post_id, reason, req_id))
                    state
                }

            }

            actor.continue(new_state)
        }



//------------------------------------------------------------------------------------------------------

        gen_types.CreatePost(send_pid, uuid, subreddit_id, post_data, req_id) -> {

            let res = {
                use user <- result.try(
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
                Ok(#(user,subreddit_id))
            }

            let new_state = case res {

                Ok(#(user, subreddit_uuid)) -> {

                    let post_uuid = uuid.v4_string()
                    let post_data = gen_types.Post(
                                    ..post_data,
                                    subreddit_id: subreddit_uuid,
                                    owner_id: user.id,
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
                    utls.send_to_pid(send_pid, #("create_post_success", post_uuid, req_id))
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_post_failed", subreddit_id, reason, req_id))
                    state
                }

            }

            actor.continue(new_state)
        }


//------------------------------------------------------------------------------------------------------

        gen_types.CreateComment(send_pid, uuid, commentable_id, comment, req_id) -> {

            let res = {
                use user <- result.try(
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
                Ok(user)
            }

            let new_state = case res {

                Ok(user) -> {

                    let comment_uuid = uuid.v4_string()
                    let comment = gen_types.Comment(
                                    ..comment,
                                    owner_id: user.id,
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
                    utls.send_to_pid(send_pid, #("create_comment_success", comment_uuid, req_id)) 
                    new_state
                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_comment_failed", commentable_id, reason, req_id))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.CreateVote(send_pid, uuid, commentable_id, vote_t, req_id) -> {

            let res = {
                use _user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use parent <- result.try(
                                    utls.check_comment_parent(
                                        commentable_id,
                                        state.posts_data,
                                        state.comments_data,
                                    )
                                )
                Ok(parent)
            }

            let new_state = case res {

                Ok(#(parent_t, parent)) -> {

                    let new_state = case parent_t, vote_t {

                        "post", "up" -> {

                            echo parent.post.owner_id
                            case dict.get(state.users_data, parent.post.owner_id) {

                                Ok(user) -> {
                                    gen_types.EngineState(
                                        ..state,
                                        posts_data: dict.insert(
                                                        state.posts_data,
                                                        commentable_id,
                                                        gen_types.Post(
                                                            ..parent.post,
                                                            upvotes: parent.post.upvotes + 1,
                                                        )
                                                    ),
                                        users_data: dict.insert(
                                                        state.users_data,
                                                        user.id,
                                                        gen_types.User(
                                                            ..user,
                                                            post_karma: user.post_karma + 1,
                                                        )
                                                    )
                                        )
                                }

                                Error(_) -> {

                                    let reason = "owner of post was invalid"
                                    utls.send_to_pid(send_pid,
                                        #("create_vote_failed", commentable_id, reason, req_id))
                                    state

                                }
                            }
                        }
                        "post", "down" -> {

                            case dict.get(state.users_data, parent.post.owner_id) {

                                Ok(user) -> {
                                    gen_types.EngineState(
                                        ..state,
                                        posts_data: dict.insert(
                                                        state.posts_data,
                                                        commentable_id,
                                                        gen_types.Post(
                                                            ..parent.post,
                                                            downvotes: parent.post.downvotes + 1,
                                                        )
                                                    ),
                                        users_data: dict.insert(
                                                        state.users_data,
                                                        user.id,
                                                        gen_types.User(
                                                            ..user,
                                                            post_karma: user.post_karma - 1,
                                                        )
                                                    )
                                        )
                                }

                                Error(_) -> {

                                    let reason = "owner of post was invalid"
                                    utls.send_to_pid(send_pid,
                                        #("create_vote_failed", commentable_id, reason, req_id))
                                    state

                                }
                            }
                        }
                        "comment", "up" -> {

                            case dict.get(state.users_data, parent.comment.owner_id) {

                                Ok(user) -> {
                                    gen_types.EngineState(
                                        ..state,
                                        comments_data: dict.insert(
                                                        state.comments_data,
                                                        commentable_id,
                                                        gen_types.Comment(
                                                            ..parent.comment,
                                                            upvotes: parent.comment.upvotes + 1,
                                                        )
                                                    ),
                                        users_data: dict.insert(
                                                        state.users_data,
                                                        user.id,
                                                        gen_types.User(
                                                            ..user,
                                                            comment_karma: user.comment_karma + 1,
                                                        )
                                                    )
                                        )
                                }

                                Error(_) -> {

                                    let reason = "owner of post was invalid"
                                    utls.send_to_pid(send_pid,
                                        #("create_vote_failed", commentable_id, reason, req_id))
                                    state

                                }
                            }
                        }
                        "comment", "down" -> {

                            case dict.get(state.users_data, parent.comment.owner_id) {

                                Ok(user) -> {
                                    gen_types.EngineState(
                                        ..state,
                                        comments_data: dict.insert(
                                                        state.comments_data,
                                                        commentable_id,
                                                        gen_types.Comment(
                                                            ..parent.comment,
                                                            downvotes: parent.comment.downvotes + 1,
                                                        )
                                                    ),
                                        users_data: dict.insert(
                                                        state.users_data,
                                                        user.id,
                                                        gen_types.User(
                                                            ..user,
                                                            comment_karma: user.comment_karma - 1,
                                                        )
                                                    )
                                        )
                                }

                                Error(_) -> {

                                    let reason = "owner of post was invalid"
                                    utls.send_to_pid(send_pid,
                                        #("create_vote_failed", commentable_id, reason, req_id))
                                    state

                                }
                            }
                        }

                        _, _ -> {

                            let reason = "illegal vote type"
                            utls.send_to_pid(send_pid,
                                #("create_vote_failed", commentable_id, reason, req_id))
                            state
                        }
                    }

                    utls.send_to_pid(send_pid, #("create_vote_success", commentable_id, req_id)) 
                    new_state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("create_vote_failed", commentable_id, reason, req_id))
                    state
                }
            }

            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.GetFeed(send_pid, uuid, req_id) -> {

            let res = {
                use user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                Ok(user)
            }

            let new_state = case res {

                Ok(user) -> {
                    let posts_list = []
                    let posts_list = list.fold(
                        user.subreddits_membership_list,
                        posts_list,
                        fn(posts_list, a) {

                            let posts = get_posts_from_subreddit(a,
                                state.subreddit_posts_map, state.posts_data, 1)

                            list.append(posts, posts_list)
                        }
                    )

                    let posts_list = posts_list|>list.map(gen_decoders.post_serializer)
                    utls.send_to_pid(send_pid, #("get_feed_success", posts_list, req_id))
                    state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("get_feed_failed", uuid, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.GetSubredditfeed(send_pid, uuid, subreddit_id, req_id) -> {

            let res = {
                use _user <- result.try(
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

                    let posts_list = get_posts_from_subreddit(subreddit_uuid,
                                state.subreddit_posts_map, state.posts_data, 5)

                    let posts_list = posts_list|>list.map(gen_decoders.post_serializer)
                    utls.send_to_pid(send_pid, #("get_subredditfeed_success", posts_list, req_id))
                    state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("get_subredditfeed_failed", subreddit_id, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.SearchUser(send_pid, uuid, search_user, req_id) -> {

            let res = {
                use _user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use search_id <- result.try(
                                    result.map_error(
                                        dict.get(state.user_rev_index, search_user),
                                        fn(_) {"no user found for name"}
                                        )
                                    )
                Ok(search_id)
            }

            let new_state = case res {

                Ok(search_id) -> {
                    utls.send_to_pid(send_pid, #("search_user_success", search_id, req_id))
                    state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("search_user_failed", search_user, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.StartDirectmessage(send_pid, uuid, to_uuid, message, req_id) -> {

            let res = {
                use from_user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use to_user <- result.try(
                                result.map_error(
                                    dict.get(state.users_data, to_uuid),
                                    fn(_) {"invalid recipient id"}
                                )
                               )
                Ok(#(from_user, to_user))
            }

            let new_state = case res {

                Ok(#(from_user, to_user)) -> {

                    let dm_id = uuid.v4_string()
                    let dm = gen_types.Dm(
                                id: dm_id,
                                msgs_list: [from_user.username<>": "<>message],
                                participants: [to_user.id, from_user.id],
                             )

                    let new_state = gen_types.EngineState(
                                        ..state,
                                        dms_data: dict.insert(state.dms_data, dm_id, dm),
                                        users_data: dict.insert(
                                                        state.users_data,
                                                        from_user.id,
                                                        gen_types.User(
                                                            ..from_user,
                                                            dms_list: [dm_id, ..from_user.dms_list]
                                                        )
                                                    )
                                                    |> dict.insert(
                                                        to_user.id,
                                                        gen_types.User(
                                                            ..to_user,
                                                            dms_list: [dm_id, ..to_user.dms_list]
                                                        )
                                                    )
                                    )
                    case dict.get(state.user_pid_map, to_user.id) {

                        Ok(to_pid) -> {
                            utls.send_to_pid(to_pid, #("start_directmessage_success", dm_id, req_id))
                            Nil
                        }
                        Error(_) -> Nil
                    }
                    new_state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("start_directmessage_failed", to_uuid, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.ReplyDirectmessage(send_pid, uuid, dm_id, message, req_id) -> {

            let res = {
                use from_user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                use dm <- result.try(
                            result.map_error(
                                dict.get(state.dms_data, dm_id),
                                fn(_) {"couldnt find dm for id"}
                                )
                            )
                Ok(#(from_user, dm))
            }

            let new_state = case res {

                Ok(#(from_user, dm)) -> {

                    let new_state = gen_types.EngineState(
                                        ..state,
                                        dms_data: dict.insert(
                                                    state.dms_data,
                                                    dm_id,
                                                    gen_types.Dm(
                                                        ..dm,
                                                        msgs_list: [
                                                            from_user.username<>": "<>message,
                                                            ..dm.msgs_list
                                                            ]
                                                    ) 
                                                  ),
                                    )
                    utls.send_to_pid(send_pid, #("reply_directmessage_success", dm_id, req_id))
                    new_state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("reply_directmessage_failed", dm_id, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }

//------------------------------------------------------------------------------------------------------

        gen_types.GetDirectmessages(send_pid, uuid, req_id) -> {

            let res = {
                use from_user <- result.try(
                                    utls.validate_request(
                                    send_pid,
                                    uuid,
                                    state.user_pid_map,
                                    state.users_data
                                    )
                                )
                Ok(from_user)
            }

            let new_state = case res {

                Ok(from_user) -> {

                    let dm_list = []
                    let dms_list = list.fold(
                        from_user.dms_list,
                        dm_list,
                        fn(acc, a) {

                            case dict.get(state.dms_data, a) {

                                Ok(dm) -> {

                                    [dm, ..acc]
                                }

                                Error(_) -> {

                                    acc
                                }
                            }
                        }
                    )
                    |> list.map(gen_decoders.dm_serializer)
                    utls.send_to_pid(send_pid, #("get_directmessages_success", dms_list, req_id))
                    state

                }

                Error(reason) -> {

                    utls.send_to_pid(send_pid, #("get_directmessages_failed", uuid, reason, req_id))
                    state
                }

            }
            actor.continue(new_state)
        }
    }
}


fn get_posts_from_subreddit(
    subreddit_id: String,
    subreddit_posts_map: Dict(String, List(String)),
    posts_data: Dict(String, gen_types.Post),
    k: Int
    ) -> List(gen_types.Post) {


    case dict.get(subreddit_posts_map, subreddit_id) {

        Ok(posts) -> {

            let i = 0
            let posts_list = []
            let #(posts_list, _) = list.fold_until(
                posts,
                #(posts_list, i),
                fn(tup, p) {

                    let #(post_list, i) = tup

                    case i < k {

                        True -> {
                            let p_l = case dict.get(posts_data, p) {

                                Ok(post) -> {

                                    [post, ..post_list]
                                }

                                Error(_) -> {

                                    post_list
                                }
                            }
                            Continue(#(p_l, i + 1))
                        }

                        False -> {

                            Stop(#(post_list, i + 1))
                        }
                    }
                }
            )
            posts_list
        }

        Error(_) -> {

            []
        }
    }
}
