import gleam/io
import gleam/int
import gleam/list
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
import client/injector

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic 

@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn create(mode: String, num_users: Int) -> Nil {

    let main_sub = process.new_subject()
    let engine_atom = atom.create("engine")
    let engine_node = atom.create("engine@localhost")

    let sub_list = dict.new()
    let builder = supervisor.new(supervisor.OneForOne)
    let #(builder, sub_list) = list.range(1, num_users) 
    |> list.fold(#(builder, sub_list), fn(acc, a) {

                            let #(build, subs) = acc
                            let res = start(a, engine_atom, engine_node)

                            let assert Ok(sub) = res
                            #(
                                supervisor.add(build, supervision.worker(fn() {res})), 
                                dict.insert(subs, a, sub.data)
                            )
                          }
        )

    let _ = supervisor.start(builder)

    case mode == "simulator" {
        True -> {
            let _ = injector.start_injection(sub_list)
            Nil
        }

        False -> {

            Nil
        }
    }


    process.receive_forever(main_sub)
    Nil
}

fn start(
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom
    ) -> actor.StartResult(process.Subject(gen_types.UserMessage)) {

    actor.new_with_initialiser(100000, fn(sub) {init(sub, id, engine_atom, engine_node)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(gen_types.UserMessage),
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom
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
                            self_sub: sub,
                            engine_pid: pid,
                            engine_atom: engine_atom,
                            user_name: "user_" <> int.to_string(id),
                            uuid: "",
                            posts: [],
                            subreddits: [],
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

        gen_types.InjectRegisterUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting register user")
            utls.send_to_engine(#("register_user", self(), state.user_name, "test_pwd"))
            actor.continue(state)

        }

        gen_types.RegisterUserFailed(name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to register user " <> name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
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

//---------------------------------------------- CreateSubreddit ----------------------------------------

        gen_types.InjectCreateSubreddit -> {

            case state.uuid == "" {

                True -> {
                    process.send_after(state.self_sub, 1000, gen_types.InjectCreateSubreddit)
                    Nil
                }

                False -> {

                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create sub reddit")
                    utls.send_to_engine(#("create_subreddit", self(), state.uuid, "test_subreddit_" <> state.user_name))
                    Nil
                }
            }
            actor.continue(state)
        }

        gen_types.CreateSubredditSuccess(subreddit_id) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully created subreddit " <> subreddit_id)
            let new_state = gen_types.UserState(
                                ..state,
                                subreddits: [subreddit_id, ..state.subreddits],
                            )

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
    }
}

fn display_feed(posts_list: List(gen_types.Post)) {

    io.println("DISPLAYING FEED...\n")
    list.each(
        posts_list,
        fn(a) {

            let gen_types.Post(title: title, body: body, ..) = a

            io.println("TITLE: "<>title<>"\n")
            io.println("--------------------------------------------------------\n")
            io.println("BODY:\n\t"<>body)
            io.println("--------------------------------------------------------\n\n")
        }
    )
}
