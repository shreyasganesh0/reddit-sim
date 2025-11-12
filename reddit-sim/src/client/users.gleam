import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/string
import gleam/dict
import gleam/dynamic/decode
import gleam/dynamic

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process
import gleam/erlang/atom
import gleam/erlang/node

import generated/generated_types as gen_types 
import generated/generated_selectors as gen_select
import generated/generated_decoders as gen_decode

import metrics/user_metrics
import utls
//import client/injector
import client/zipf

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic 

@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn create(mode: String, num_users: Int, run_time: Int) -> Nil {

    let main_sub = process.new_subject()
    let engine_atom = atom.create("engine")
    let engine_node = atom.create("engine@localhost")
    let metrics_atom = atom.create("metrics")
    let metrics_node = atom.create("metrics@localhost")

    let cdf = case mode == "simulator" {
        True -> {
            let n = 100
            let cdf = zipf.create_cdf(n)

            //let _ = injector.start_injection(sub_list)
            cdf
        }

        False -> {

            []
        }
    }

    let ninetyp = {num_users * 90} / 100 
    let one = {num_users * 1} / 100 
    let onep = case one { 

        0 -> 1

        _ -> one
    }
    let sub_list = dict.new()
    let builder = supervisor.new(supervisor.OneForOne)
    let #(builder, sub_list) = list.range(1, num_users) 
    |> list.fold(#(builder, sub_list), fn(acc, a) {

                            let #(build, subs) = acc
                            let role = case a <= onep {

                                True -> "creator"

                                False -> {

                                    case a < ninetyp + onep {

                                        True -> "lurker"

                                        False -> "contributor"
                                    }
                                }
                            }

                            let res = start(a, engine_atom, engine_node, metrics_atom, metrics_node, cdf, main_sub, role)

                            let assert Ok(sub) = res
                            #(
                                supervisor.add(
                                    build,
                                    supervision.worker(fn() {res})
                                    |> supervision.restart(supervision.Transient)
                                ), 
                                dict.insert(subs, a - 1, sub.data)
                            )
                          }
        )

    let _ = supervisor.start(builder)

    case mode == "simulator" {

        True -> {

            let r_list = []
            dict.fold(
                sub_list,
                r_list,
                fn(acc, i, a) {

                    case i == 0 {
                        
                        True -> {

                            zipf.create_subreddits_list(100, a)

                            let t = []

                            io.println("sending creation messages")
                            let l = list.range(1, 100)
                            |>list.fold(
                                t,
                                fn(acc, _a) {
                                    [process.receive_forever(main_sub), ..acc]
                                }
                            )
                            process.send(a, gen_types.InjectThinkingMessage)
                            process.send_after(a, run_time, gen_types.InjectShutdownMessage)
                            l
                        }

                        False -> {

                            process.send(a, gen_types.UpdateSubredditsList(acc))
                            process.send_after(a, run_time, gen_types.InjectShutdownMessage)
                            acc
                        }

                    }
                }
            )
        }

        False -> {

            []
        }
    }

    dict.each(sub_list, fn(_, _) {process.receive_forever(main_sub)})
    io.println("SIMULATION COMPLETE>>>")
    Nil
}

fn start(
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom,
    metrics_atom: atom.Atom,
    metrics_node: atom.Atom,
    cdf: List(Float),
    main_sub: process.Subject(String),
    role: String
    ) -> actor.StartResult(process.Subject(gen_types.UserMessage)) {

    actor.new_with_initialiser(100000, fn(sub) {init(sub, id, engine_atom, engine_node, metrics_atom, metrics_node, cdf, main_sub, role)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(gen_types.UserMessage),
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom,
    metrics_atom: atom.Atom,
    metrics_node: atom.Atom,
    cdf: List(Float),
    main_sub: process.Subject(String),
    role: String,
    ) -> Result(
            actor.Initialised(
                gen_types.UserState, 
                gen_types.UserMessage, 
                process.Subject(gen_types.UserMessage)
                ), 
                String
         ) {

        case node.connect(engine_node) {
            
            Ok(_node) -> {

                io.println("Connected to engine")
            }

            Error(err) -> {

                case err {

                    node.FailedToConnect -> io.println("Node failed to connect")

                    node.LocalNodeIsNotAlive -> io.println("Not in distributed mode")
                }
            }

        }

        case node.connect(metrics_node) {
            
            Ok(_node) -> {

                io.println("Connected to metrics")
            }

            Error(err) -> {

                case err {

                    node.FailedToConnect -> io.println("Node failed to connect")

                    node.LocalNodeIsNotAlive -> io.println("Not in distributed mode")
                }
            }

        }

        case id == 1 {
            True -> { 
                process.sleep(500)
                Nil
            }

            False -> Nil
        }
        let data = global_whereisname(engine_atom)
        let pid = case decode.run(data, gen_decode.pid_decoder()) {

            Ok(engine_pid) -> {

                io.println("Found engine's pid")
                engine_pid
            }

            Error(_) -> {

                io.println("Couldnt find engine's pid")
                panic
            }
        }

        let data = global_whereisname(metrics_atom)
        let metrics_pid = case decode.run(data, gen_decode.pid_decoder()) {

            Ok(metrics_pid) -> {

                io.println("Found metrics's pid")
                metrics_pid
            }

            Error(_) -> {

                io.println("Couldnt find metric's pid")
                panic
            }
        }
        
        let init_state = gen_types.UserState(
                            id: id,
                            zipf_rank: 1.0 /. int.to_float(id),
                            self_sub: sub,
                            main_sub: main_sub,
                            engine_pid: pid,
                            engine_atom: engine_atom,
                            metrics_pid: metrics_pid,
                            user_name: "user_" <> int.to_string(id),
                            uuid: "",
                            posts: [],
                            subreddits: [],
                            comments: [],
                            users: [],
                            dms: [],
                            cdf: cdf,
                            sub_count: 0,
                            role: role,
                            pending_reqs: dict.new(),
                         )


        let selector = process.new_selector() 
        let selector_tag_list = gen_select.get_user_selector_list() 

        let selector = utls.create_selector(selector, selector_tag_list)
        |> process.select_map(sub, fn(msg) {msg})

        let ret = actor.initialised(init_state)
        |> actor.returning(sub)
        |> actor.selecting(selector)

        //process.send(sub, gen_types.UserTestMessage)

        Ok(ret)
}

fn get_fsm_actions(state: gen_types.UserState) -> List(gen_types.UserMessage) {

    let possible = case state.uuid == "" {

        True -> [gen_types.InjectRegisterUser]

        False -> {

            let possible = [
                            gen_types.InjectGetFeed,
                            gen_types.InjectGetSubredditfeed,
                            gen_types.InjectSearchUser,
                            gen_types.InjectGetDirectmessages,
                            gen_types.InjectCreateSubreddit,
                            gen_types.InjectJoinSubreddit
                           ]

            let possible = case list.is_empty(state.subreddits) {

                True -> possible 

                False -> [ gen_types.InjectCreatePost,
                            gen_types.InjectLeaveSubreddit, ..possible]
            } 

            let possible = case !list.is_empty(state.posts) {

                True -> [gen_types.InjectCreateRepost, gen_types.InjectCreateComment, gen_types.InjectCreateVote, ..possible]

                False -> possible
            }

            let possible = case !list.is_empty(state.users) {

                True -> [gen_types.InjectStartDirectmessage, ..possible]

                False -> possible
            }

            case !list.is_empty(state.dms) {
                True -> [gen_types.InjectReplyDirectmessage, ..possible]

                False -> possible
            }
        }

    }

  possible
}

fn filter_by_user_type(role: String) -> List(gen_types.UserMessage) {

    let l = case role {


        "contributor" -> {

            [
            gen_types.InjectJoinSubreddit,
            gen_types.InjectLeaveSubreddit,
            gen_types.InjectGetFeed,
            gen_types.InjectGetSubredditfeed,
            gen_types.InjectCreateComment,
            gen_types.InjectCreateVote,
            gen_types.InjectReplyDirectmessage,
            gen_types.InjectGetDirectmessages,
            gen_types.InjectSearchUser,
            ]
        }

        "creator" -> {

            [
            gen_types.InjectCreatePost,
            gen_types.InjectCreateRepost,
            gen_types.InjectCreateSubreddit,
            gen_types.InjectJoinSubreddit,
            gen_types.InjectLeaveSubreddit,
            gen_types.InjectGetFeed,
            gen_types.InjectGetSubredditfeed,
            gen_types.InjectCreateComment,
            gen_types.InjectCreateVote,
            gen_types.InjectStartDirectmessage,
            gen_types.InjectReplyDirectmessage,
            gen_types.InjectGetDirectmessages,
            gen_types.InjectSearchUser,
            ]
        }

        _ -> {

            [
            gen_types.InjectJoinSubreddit,
            gen_types.InjectLeaveSubreddit,
            gen_types.InjectGetFeed,
            gen_types.InjectGetSubredditfeed,
            gen_types.InjectSearchUser,
            ]
        }
    }

    [gen_types.InjectRegisterUser, ..l]
}

fn find_subreddit_to_send(subreddit_idx: Int, subreddits: List(String)) -> String {

    let send_sub = ""
    list.index_fold(
        subreddits,
        send_sub,
        fn(acc, subreddit_id, i) {

            case i == subreddit_idx {

                True -> {

                    subreddit_id
                }

                False -> {

                    acc
                }
            }
        }
    )
}


fn filter_by_action_type() -> gen_types.UserMessage {

    let r = float.random()
    case r <. 0.85 {

        True -> {

            let in_r = float.random()

            case in_r <. 0.85 {

                True -> gen_types.InjectGetFeed

                False -> {

                    case in_r <. 0.99 {

                        True -> gen_types.InjectGetSubredditfeed

                        False -> gen_types.InjectGetDirectmessages
                    }
                }
            } 
        }

        False -> {

            case r <. 0.98 {

                True -> {

                    let in_r = float.random()
                    case in_r <. 0.85 {
                         
                        True -> gen_types.InjectCreateVote

                        False -> {

                            case in_r <. 0.99 {

                                True -> gen_types.InjectCreateComment

                                False -> gen_types.InjectReplyDirectmessage
                            }
                        }
                    }
                }

                False -> {

                    case r <. 0.999 {

                        True -> {

                            let in_r = float.random()
                            case in_r <. 0.90 { 

                                True -> gen_types.InjectCreatePost

                                False -> {

                                    case in_r <. 0.99 {

                                        True -> gen_types.InjectCreateRepost

                                        False -> gen_types.InjectStartDirectmessage
                                    }
                                }
                            }
                        }

                        False -> {

                            let in_r = float.random()
                            case in_r <. 0.90 { 

                                True -> gen_types.InjectCreateSubreddit

                                False -> {

                                    case in_r <. 0.99 {

                                        True -> gen_types.InjectSearchUser

                                        False -> {

                                            case in_r <. 0.998 {

                                                True -> gen_types.InjectJoinSubreddit

                                                False -> gen_types.InjectLeaveSubreddit
                                            }
                                        }
                                    }
                                }
                            } 
                        }
                    }
                }
            }
        }
    } 
}


fn distribute_message(state: gen_types.UserState) -> Nil {

    let possible_message = get_fsm_actions(state)
    |> list.filter(fn(a) {list.contains(filter_by_user_type(state.role), a)}) 

    case possible_message {

        [] -> Nil

        [one] -> {

            //assert one == gen_types.InjectRegisterUser
            process.send(state.self_sub, one)
        }

        _ -> {

            let msg = filter_by_action_type()
            case list.filter(
                possible_message,
                fn(a) {
                msg == a}) {

                [msg] -> process.send(state.self_sub, msg)

                _ -> Nil
            }
            
        }
    }

}

fn handle_user(
    state: gen_types.UserState,
    msg: gen_types.UserMessage
    ) -> actor.Next(gen_types.UserState, gen_types.UserMessage) {

    case msg {

        gen_types.InjectShutdownMessage -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " disconnecting")
            utls.send_to_engine(#("shutdown_user", state.user_name))
            user_metrics.send_shutdown(state.metrics_pid)
            process.send(state.main_sub, "")
            actor.stop()
        }

//---------------------------------------------- DisconnectUser -------------------------------------------
        gen_types.InjectDisconnectReconnect -> {


            let delay = 10000.0 /. state.zipf_rank |> float.round
            let jitter = int.random(delay/4)

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " disconnecting")
            process.sleep(delay + jitter)
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " reconnecting")

            actor.continue(state)
        }
//---------------------------------------------- ThinkingMessage -------------------------------------------
        gen_types.InjectThinkingMessage -> {

            distribute_message(state)

            let delay = 1000.0 /. state.zipf_rank |> float.round
            let jitter = int.random(delay/4)

            process.send_after(state.self_sub, delay + jitter, gen_types.InjectThinkingMessage)
            actor.continue(state)
        }

//---------------------------------------------- UpdateSubredditsList ---------------------------------------

        gen_types.UpdateSubredditsList(subs) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " updating subreddits")
            let new_state = gen_types.UserState(
                                ..state,
                                subreddits: list.append(subs, state.subreddits)
                            )
            process.send(state.self_sub, gen_types.InjectThinkingMessage)
            actor.continue(new_state)
        }


//---------------------------------------------- RegisterUser -------------------------------------------

        gen_types.InjectRegisterUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting register user")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let new_state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(#("register_user", self(), state.user_name, "test_pwd", req_id))

            actor.continue(new_state)

        }


        gen_types.RegisterUserSuccess(user_id, req_id) -> {

            io.println("[CLIENT]: registered client with uuid: " <> user_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "register_user", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                uuid: user_id, 
                                pending_reqs: new_pending,
                            )
            actor.continue(new_state)
        }

        gen_types.RegisterUserFailed(name, fail_reason, req_id) -> {


            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to register user " <> name <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "register_user", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(new_state)
        }

//---------------------------------------------- LoginUser -------------------------------------------

        gen_types.InjectLoginUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting login user")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let new_state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(#("login_user", self(), state.user_name, "test_pwd", req_id))

            actor.continue(new_state)

        }


        gen_types.LoginUserSuccess(user_id, req_id) -> {

            io.println("[CLIENT]: login client with uuid: " <> user_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "login_user", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                uuid: user_id, 
                                pending_reqs: new_pending,
                            )
            actor.continue(new_state)
        }

        gen_types.LoginUserFailed(name, fail_reason, req_id) -> {


            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to login user " <> name <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "register_user", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(new_state)
        }


//---------------------------------------------- CreateSubreddit ----------------------------------------

        gen_types.InjectCreateSubreddit -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create sub reddit")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let new_state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
                sub_count: state.sub_count + 1
            )

            utls.send_to_engine(#("create_subreddit", self(), state.uuid,
                "subreddit_"<>int.to_string(state.sub_count), req_id))
            actor.continue(new_state)
        }

        gen_types.CreateSubredditSuccess(subreddit_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully created subreddit " <> subreddit_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "create_subreddit", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                subreddits: [subreddit_id, ..state.subreddits],
                            )

            process.send(state.main_sub, subreddit_id)

            actor.continue(new_state)
        }

        gen_types.CreateSubredditFailed(subreddit_name, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to create subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "create_subreddit", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- JoinSubreddit ------------------------------------------
        gen_types.InjectJoinSubreddit -> {

            let subreddit_id = zipf.sample_zipf(state.cdf)
            |> find_subreddit_to_send(state.subreddits)

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting join subreddit")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(#("join_subreddit", self(), state.uuid, subreddit_id, req_id))
            actor.continue(state)
        }

        gen_types.JoinSubredditSuccess(subreddit_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully joined subreddit " <> subreddit_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "join_subreddit", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                subreddits: [subreddit_id, ..state.subreddits],
                            )

            actor.continue(new_state)
        }

        gen_types.JoinSubredditFailed(subreddit_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to join subreddit " <> subreddit_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "join_subreddit", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- JoinSubreddit ------------------------------------------
        gen_types.InjectLeaveSubreddit -> {

            let subreddit_id = zipf.sample_zipf(state.cdf)
            |> find_subreddit_to_send(state.subreddits)

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting leave subreddit")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(#("leave_subreddit", self(), state.uuid, subreddit_id, req_id))
            actor.continue(state)
        }

        gen_types.LeaveSubredditSuccess(subreddit_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully left subreddit " <> subreddit_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "leave_subreddit", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                subreddits: 
                                    list.drop_while(
                                        state.subreddits,
                                        fn(a) {a==subreddit_id},
                                    )
                            )

            actor.continue(new_state)
        }

        gen_types.LeaveSubredditFailed(subreddit_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to leave subreddit " <> subreddit_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "join_subreddit", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- CreatePost -------------------------------------------

        gen_types.InjectCreatePost -> {

            let subreddit_id = zipf.sample_zipf(state.cdf)
            |> find_subreddit_to_send(state.subreddits)

            let post = gen_types.Post(
                        id: "",
                        title: "test title",
                        body: "post_body:"<>int.to_string(int.random(10000)),
                        owner_id: "",
                        subreddit_id: subreddit_id,
                        upvotes: 0,
                        downvotes: 0,
                       )
            |> gen_decode.post_serializer
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create post")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "create_post",
                    self(), 
                    state.uuid,
                    subreddit_id,
                    post,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.CreatePostSuccess(post_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully posted to subreddit " <> post_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "create_post", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                posts: [post_id, ..state.posts],
                            )

            actor.continue(new_state)
        }

        gen_types.CreatePostFailed(subreddit_name, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to post to subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "create_post", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- CreateRepost -------------------------------------------

        gen_types.InjectCreateRepost -> {

            let assert [post_to_send] = list.sample(state.posts, 1)
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create post")
            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "create_repost",
                    self(), 
                    state.uuid,
                    post_to_send,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.CreateRepostSuccess(post_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully posted to subreddit " <> post_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "create_repost", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                posts: [post_id, ..state.posts],
                            )

            actor.continue(new_state)
        }

        gen_types.CreateRepostFailed(post_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to repost " <> post_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "create_repost", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }



//---------------------------------------------- CreateComment -------------------------------------------
        gen_types.InjectCreateComment -> {

            let assert [post_to_send] = list.sample(list.append(state.posts, state.comments), 1)
            let comment = gen_types.Comment(
                        id: "",
                        body: "comment_body",
                        parent_id: "",
                        owner_id: "",
                        upvotes: 0,
                        downvotes: 0,
                       )
            |> gen_decode.comment_serializer
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create comment")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "create_comment",
                    self(), 
                    state.uuid,
                    post_to_send,
                    comment,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.CreateCommentSuccess(comment_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully comment to parent " <> comment_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "create_comment", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                comments: [comment_id, ..state.comments]
                            )
            actor.continue(new_state)
        }

        gen_types.CreateCommentFailed(parent_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to comment to parent " <> parent_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "create_comment", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- CreateVote -------------------------------------------

        gen_types.InjectCreateVote -> {
            
            let assert [post_to_send] = list.sample(state.posts, 1)
            let vote_t = "up"
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting vote")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "create_vote",
                    self(), 
                    state.uuid,
                    post_to_send,
                    vote_t,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.CreateVoteSuccess(parent_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully voted to parent " <> parent_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "create_vote", state.pending_reqs, state.metrics_pid)
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )

            actor.continue(new_state)
        }

        gen_types.CreateVoteFailed(parent_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to vote to parent " <> parent_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "create_vote", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- GetFeed ---------------------------------------------

        gen_types.InjectGetFeed -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting get feed")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "get_feed",
                    self(), 
                    state.uuid,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.GetFeedSuccess(posts_list, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully got feed") 

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "get_feed", state.pending_reqs, state.metrics_pid)
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )

            display_feed(posts_list)
            actor.continue(new_state)
        }

        gen_types.GetFeedFailed(user_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to get feed for user " <> user_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "get_feed", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )

            actor.continue(state)
        }
//---------------------------------------------- GetSubredditfeed ---------------------------------------------

        gen_types.InjectGetSubredditfeed -> {

            let subreddit_to_send = zipf.sample_zipf(state.cdf)
                                            |> find_subreddit_to_send(state.subreddits)
            echo subreddit_to_send
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting get subreddit feed")

            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "get_subredditfeed",
                    self(), 
                    state.uuid,
                    subreddit_to_send,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.GetSubredditfeedSuccess(posts_list, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully got subreddit feed") 

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "get_subredditfeed", state.pending_reqs, state.metrics_pid)


            let posts = display_feed(posts_list)
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                posts: list.append(posts, state.posts)
                            )
            actor.continue(new_state)
        }

        gen_types.GetSubredditfeedFailed(subreddit_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to get subreddit feed from parent " <> subreddit_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "get_subredditfeed", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- SearchUser ---------------------------------------------

        gen_types.InjectSearchUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting search user")
            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "search_user",
                    self(), 
                    state.uuid,
                    "user_"<>int.to_string(int.random(1000)),
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.SearchUserSuccess(user_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully found user" <> user_id)

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "search_user", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                users: [user_id, ..state.users]
                            )
            actor.continue(new_state)
        }

        gen_types.SearchUserFailed(user_name, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to find user " <> user_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "search_user", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- StartDirectmessage ---------------------------------------------

        gen_types.InjectStartDirectmessage -> {

            let assert [user_to_send] = list.sample(state.users, 1)
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting start dm")
            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "start_directmessage",
                    self(), 
                    state.uuid,
                    user_to_send,
                    "test_dm"<>int.to_string(int.random(1000)),
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.StartDirectmessageSuccess(dm_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully started dm") 

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "start_directmessage", state.pending_reqs, state.metrics_pid)

            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                dms: [dm_id, ..state.dms]
                            )
            actor.continue(new_state)
        }

        gen_types.StartDirectmessageFailed(to_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to start dm " <> to_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "start_directmessage", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }

//---------------------------------------------- ReplyDirectmessage ---------------------------------------------

        gen_types.InjectReplyDirectmessage -> {

            let assert [dm_to_send] = list.sample(state.dms, 1)
            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting reply dm")
            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "reply_directmessage",
                    self(), 
                    state.uuid,
                    dm_to_send,
                    "test_reply"<>int.to_string(int.random(1000)),
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.ReplyDirectmessageSuccess(dm_id, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully replied "<>dm_id) 

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "reply_directmessage", state.pending_reqs, state.metrics_pid)
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )

            actor.continue(state)
        }

        gen_types.ReplyDirectmessageFailed(dm_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to reply " <> dm_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "reply_directmessage", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }
//---------------------------------------------- GetDirectmessages ---------------------------------------------

        gen_types.InjectGetDirectmessages -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting get directmessages")
            let #(req_id, new_pending) = user_metrics.send_to_engine(state.pending_reqs)

            let state = gen_types.UserState(
                ..state,
                pending_reqs: new_pending,
            )
            utls.send_to_engine(
                #(
                    "get_directmessages",
                    self(), 
                    state.uuid,
                    req_id
                )
            )
            actor.continue(state)
        }
        
        gen_types.GetDirectmessagesSuccess(dms_list, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully got dms ") 

            let new_pending = user_metrics.send_timing_metrics(
                req_id, "get_directmessages", state.pending_reqs, state.metrics_pid)

            let dms = display_dms(dms_list)
            let new_state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                                dms: list.append(dms, state.dms)
                            )
            actor.continue(new_state)
        }

        gen_types.GetDirectmessagesFailed(user_id, fail_reason, req_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to get dms " <> user_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")

            utls.send_to_pid(
                state.metrics_pid, 
                #("record_action", "get_directmessages", "failed")
            )
            let new_pending = dict.drop(state.pending_reqs, [req_id])
            let state = gen_types.UserState(
                                ..state,
                                pending_reqs: new_pending,
                            )
            actor.continue(state)
        }
    }
}

fn display_dms(dms_list: List(gen_types.Dm)) -> List(String) {

    io.println("DISPLAYING DMS...\n")
    let dm_id_list = []
    list.fold(
        dms_list,
        dm_id_list,
        fn(acc, a) {

            io.println("Participants:"<>a.participants|>string.join(", "))
            io.println("--------------------------------------------------------\n")
            io.println("Messages:"<>a.msgs_list|>string.join("\n"))
            io.println("\n--------------------------------------------------------\n")
            [a.id, ..acc]
        }
    )
}
fn display_feed(posts_list: List(gen_types.Post)) -> List(String) {

    let post_id_list = []
    io.println("DISPLAYING FEED...\n")
    list.fold(
        posts_list,
        post_id_list,
        fn(acc, a) {

            let gen_types.Post(title: title, body: body, subreddit_id: subreddit_id, ..) = a

            io.println("SUBREDDIT: "<>subreddit_id<>"\n")
            io.println("--------------------------------------------------------\n")
            io.println("TITLE: "<>title<>"\n")
            io.println("\n--------------------------------------------------------\n")
            io.println("BODY:\n\t"<>body)
            io.println("--------------------------------------------------------\n\n")
            [a.id, ..acc]
        }
    )
}
