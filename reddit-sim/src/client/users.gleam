import gleam/io
import gleam/int
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
import utls
//import client/injector
import client/zipf

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic 

@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn create(mode: String, num_users: Int) -> Nil {

    let main_sub = process.new_subject()
    let engine_atom = atom.create("engine")
    let engine_node = atom.create("engine@localhost")

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
    let sub_list = dict.new()
    let builder = supervisor.new(supervisor.OneForOne)
    let #(builder, sub_list) = list.range(1, num_users) 
    |> list.fold(#(builder, sub_list), fn(acc, a) {

                            let #(build, subs) = acc

                            let res = start(a, engine_atom, engine_node, cdf, main_sub)

                            let assert Ok(sub) = res
                            #(
                                supervisor.add(build, supervision.worker(fn() {res})), 
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
                            list.range(1, 100)
                            |>list.fold(
                                t,
                                fn(acc, _a) {
                                    [process.receive_forever(main_sub), ..acc]
                                }
                            )
                        }

                        False -> {

                            process.send(a, gen_types.UpdateSubredditsList(acc))
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



    process.receive_forever(main_sub)
    Nil
}

fn start(
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom,
    cdf: List(Float),
    main_sub: process.Subject(String)
    ) -> actor.StartResult(process.Subject(gen_types.UserMessage)) {

    actor.new_with_initialiser(100000, fn(sub) {init(sub, id, engine_atom, engine_node, cdf, main_sub)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(gen_types.UserMessage),
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom,
    cdf: List(Float),
    main_sub: process.Subject(String)
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

        process.sleep(1000)
        let data = global_whereisname(engine_atom)
        let pid = case decode.run(data, gen_decode.pid_decoder(data)) {

            Ok(engine_pid) -> {

                io.println("Found engine's pid")
                engine_pid
            }

            Error(_) -> {

                io.println("Couldnt find engine's pid")
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
                            user_name: "user_" <> int.to_string(id),
                            uuid: "",
                            posts: [],
                            subreddits: [],
                            users: [],
                            dms: [],
                            cdf: cdf,
                            sub_count: 0,
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

fn handle_user(
    state: gen_types.UserState,
    msg: gen_types.UserMessage
    ) -> actor.Next(gen_types.UserState, gen_types.UserMessage) {

    case msg {


//---------------------------------------------- RegisterUser -------------------------------------------

        gen_types.UpdateSubredditsList(subs) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " updating subreddits")
            let new_state = gen_types.UserState(
                                ..state,
                                subreddits: list.append(subs, state.subreddits)
                            )
            actor.continue(new_state)
        }


//---------------------------------------------- RegisterUser -------------------------------------------

        gen_types.InjectRegisterUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting register user")
            utls.send_to_engine(#("register_user", self(), state.user_name, "test_pwd"))
            actor.continue(state)

        }


        gen_types.RegisterUserSuccess(uuid) -> {

            io.println("[CLIENT]: registered client with uuid: " <> uuid)
            let new_state = gen_types.UserState(
                                ..state,
                                uuid: uuid
                            )
            actor.continue(new_state)
        }

        gen_types.RegisterUserFailed(name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to register user " <> name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- CreateSubreddit ----------------------------------------

        gen_types.InjectCreateSubreddit -> {

            let new_state = case state.uuid == "" {

                True -> {
                    process.send_after(state.self_sub, 1000, gen_types.InjectCreateSubreddit)
                    state
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create sub reddit")
                    utls.send_to_engine(#("create_subreddit", self(), state.uuid,
                        "subreddit_"<>int.to_string(state.sub_count)))
                     gen_types.UserState(
                                        ..state,
                                        sub_count: state.sub_count + 1
                                    )
                    
                }
            }
            actor.continue(new_state)
        }

        gen_types.CreateSubredditSuccess(subreddit_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully created subreddit " <> subreddit_id)
            let new_state = gen_types.UserState(
                                ..state,
                                subreddits: [subreddit_id, ..state.subreddits],
                            )
            process.send(state.main_sub, subreddit_id)

            actor.continue(new_state)
        }

        gen_types.CreateSubredditFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to create subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- JoinSubreddit ------------------------------------------

        gen_types.InjectJoinSubreddit -> {

            case state.uuid == "" {

                True -> {

                    process.send_after(state.self_sub, 2000, gen_types.InjectJoinSubreddit)
                    Nil
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting join subreddit")
                    utls.send_to_engine(#("join_subreddit", self(), state.uuid, "test_subreddit_user_1"))
                    Nil
                }
            }
            actor.continue(state)
        }

        gen_types.JoinSubredditSuccess(subreddit_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully joined subreddit " <> subreddit_id)
            let new_state = gen_types.UserState(
                                ..state,
                                subreddits: [subreddit_id, ..state.subreddits],
                            )

            actor.continue(new_state)
        }

        gen_types.JoinSubredditFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to join subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- CreatePost -------------------------------------------

        gen_types.InjectCreatePost -> {

            case state.uuid == "" || state.subreddits == [] {

                True -> {

                    process.send_after(state.self_sub, 3000, gen_types.InjectCreatePost)
                    Nil
                }

                False -> {
                    let assert Ok(subreddit_to_send) = list.first(state.subreddits)
                    let post = gen_types.Post(
                                id: "",
                                title: "test title",
                                body: "post_body",
                                owner_id: "",
                                upvotes: 0,
                                downvotes: 0,
                               )
                    |> gen_decode.post_serializer
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create post")
                    utls.send_to_engine(
                        #(
                            "create_post",
                            self(), 
                            state.uuid,
                            subreddit_to_send,
                            post
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.CreatePostSuccess(post_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully posted to subreddit " <> post_id)

            let new_state = gen_types.UserState(
                                ..state,
                                posts: [post_id, ..state.posts],
                            )

            actor.continue(new_state)
        }

        gen_types.CreatePostFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to post to subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }


//---------------------------------------------- CreateComment -------------------------------------------
        gen_types.InjectCreateComment -> {

            case state.uuid == "" || state.posts == [] {

                True -> {

                    process.send_after(state.self_sub, 4000, gen_types.InjectCreateComment)
                    Nil
                }

                False -> {

                    let assert Ok(post_to_send) = list.first(state.posts)
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
                    utls.send_to_engine(
                        #(
                            "create_comment",
                            self(), 
                            state.uuid,
                            post_to_send,
                            comment
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.CreateCommentSuccess(parent_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully comment to parent " <> parent_id)
            actor.continue(state)
        }

        gen_types.CreateCommentFailed(parent_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to comment to parent " <> parent_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- CreateVote -------------------------------------------

        gen_types.InjectCreateVote -> {

            case state.uuid == "" || state.posts == [] {

                True -> {

                    process.send_after(state.self_sub, 5000, gen_types.InjectCreateVote)
                    Nil
                }

                False -> {

                    let assert Ok(post_to_send) = list.first(state.posts)
                    let vote_t = "up"
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting vote")
                    utls.send_to_engine(
                        #(
                            "create_vote",
                            self(), 
                            state.uuid,
                            post_to_send,
                            vote_t
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.CreateVoteSuccess(parent_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully voted to parent " <> parent_id)
            actor.continue(state)
        }

        gen_types.CreateVoteFailed(parent_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to vote to parent " <> parent_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- GetFeed ---------------------------------------------

        gen_types.InjectGetFeed -> {

            case state.uuid == "" || state.subreddits == [] {

                True -> {

                    process.send_after(state.self_sub, 5000, gen_types.InjectGetFeed)
                    Nil
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting vote")
                    utls.send_to_engine(
                        #(
                            "get_feed",
                            self(), 
                            state.uuid,
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.GetFeedSuccess(posts_list) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully voted to parent ") 

            display_feed(posts_list)
            actor.continue(state)
        }

        gen_types.GetFeedFailed(user_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to vote to parent " <> user_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }
//---------------------------------------------- GetSubredditfeed ---------------------------------------------

        gen_types.InjectGetSubredditfeed -> {

            case state.uuid == "" || state.subreddits == [] {

                True -> {

                    process.send_after(state.self_sub, 5000, gen_types.InjectGetSubredditfeed)
                    Nil
                }

                False -> {

                    let assert Ok(subreddit_to_send) = list.first(state.subreddits)
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting vote")
                    utls.send_to_engine(
                        #(
                            "get_subredditfeed",
                            self(), 
                            state.uuid,
                            subreddit_to_send,
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.GetSubredditfeedSuccess(posts_list) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully voted to parent ") 

            let posts = display_feed(posts_list)
            let new_state = gen_types.UserState(
                                ..state,
                                posts: list.append(posts, state.posts)
                            )
            actor.continue(new_state)
        }

        gen_types.GetSubredditfeedFailed(subreddit_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to vote to parent " <> subreddit_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- SearchUser ---------------------------------------------

        gen_types.InjectSearchUser -> {

            case state.uuid == "" {

                True -> {

                    process.send_after(state.self_sub, 5000, gen_types.InjectSearchUser)
                    Nil
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting search user")
                    utls.send_to_engine(
                        #(
                            "search_user",
                            self(), 
                            state.uuid,
                            "user_"<>int.to_string({state.id + 1}),
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.SearchUserSuccess(user_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully found user" <> user_id) 

            let new_state = gen_types.UserState(
                                ..state,
                                users: [user_id, ..state.users]
                            )
            actor.continue(new_state)
        }

        gen_types.SearchUserFailed(user_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to find user " <> user_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- StartDirectmessage ---------------------------------------------

        gen_types.InjectStartDirectmessage -> {

            case state.uuid == "" || state.users == [] {

                True -> {

                    process.send_after(state.self_sub, 5000, gen_types.InjectStartDirectmessage)
                    Nil
                }

                False -> {

                    let assert Ok(user_to_send) = list.first(state.users)
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting start dm")
                    utls.send_to_engine(
                        #(
                            "start_directmessage",
                            self(), 
                            state.uuid,
                            user_to_send,
                            "test_dm"
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.StartDirectmessageSuccess(dm_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully started dm") 

            let new_state = gen_types.UserState(
                                ..state,
                                dms: [dm_id, ..state.dms]
                            )
            actor.continue(new_state)
        }

        gen_types.StartDirectmessageFailed(to_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to start dm " <> to_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- ReplyDirectmessage ---------------------------------------------

        gen_types.InjectReplyDirectmessage -> {

            case state.uuid == "" || state.dms == [] {

                True -> {

                    process.send_after(state.self_sub, 6000, gen_types.InjectReplyDirectmessage)
                    Nil
                }

                False -> {

                    let assert Ok(dm_to_send) = list.first(state.dms)
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting reply dm")
                    utls.send_to_engine(
                        #(
                            "reply_directmessage",
                            self(), 
                            state.uuid,
                            dm_to_send,
                            "test_reply"
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.ReplyDirectmessageSuccess(dm_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully replied "<>dm_id) 

            actor.continue(state)
        }

        gen_types.ReplyDirectmessageFailed(dm_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to reply " <> dm_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }
//---------------------------------------------- GetDirectmessages ---------------------------------------------

        gen_types.InjectGetDirectmessages -> {

            case state.uuid == "" || state.dms == []{

                True -> {

                    process.send_after(state.self_sub, 7000, gen_types.InjectGetDirectmessages)
                    Nil
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting get directmessages")
                    utls.send_to_engine(
                        #(
                            "get_directmessages",
                            self(), 
                            state.uuid,
                        )
                    )
                    Nil
                }
            }
            actor.continue(state)
        }
        
        gen_types.GetDirectmessagesSuccess(dms_list) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully got dms ") 

            let dms = display_dms(dms_list)
            let new_state = gen_types.UserState(
                                ..state,
                                dms: list.append(dms, state.dms)
                            )
            actor.continue(new_state)
        }

        gen_types.GetDirectmessagesFailed(user_id, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to get dms " <> user_id <> " \n|||| REASON: " <> fail_reason <> " |||\n")
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

            let gen_types.Post(title: title, body: body, ..) = a

            io.println("TITLE: "<>title<>"\n")
            io.println("--------------------------------------------------------\n")
            io.println("BODY:\n\t"<>body)
            io.println("--------------------------------------------------------\n\n")
            [a.id, ..acc]
        }
    )
}
