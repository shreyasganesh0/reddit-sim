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

import types
import selectors
import utls
import decoders
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
    ) -> actor.StartResult(process.Subject(types.UserMessage)) {

    actor.new_with_initialiser(100000, fn(sub) {init(sub, id, engine_atom, engine_node)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(types.UserMessage),
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom
    ) -> Result(
            actor.Initialised(
                types.UserState, 
                types.UserMessage, 
                process.Subject(types.UserMessage)
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
        let pid = case decode.run(data, decoders.pid_decoder(data)) {

            Ok(engine_pid) -> {

                io.println("Found engine's pid")
                engine_pid
            }

            Error(_) -> {

                io.println("Couldnt find engine's pid")
                panic
            }
        }
        
        let init_state = types.UserState(
                            id: id,
                            self_sub: sub,
                            engine_pid: pid,
                            engine_atom: engine_atom,
                            user_name: "user_" <> int.to_string(id),
                            uuid: ""
                         )

        let selector = process.new_selector() 
        let selector_tag_list = get_selector_list() 

        let selector = utls.create_selector(selector, selector_tag_list)
        |> process.select_map(sub, fn(msg) {msg})

        let ret = actor.initialised(init_state)
        |> actor.returning(sub)
        |> actor.selecting(selector)

        //process.send(sub, types.UserTestMessage)

        Ok(ret)
}

fn get_selector_list() -> List(#(String, fn(dynamic.Dynamic) -> types.UserMessage, Int)) {
            [
                #("register_user_failed", selectors.register_user_failed_selector, 0),
                #("register_user_success", selectors.register_user_success_selector, 1),
                #("create_subreddit_success", selectors.create_subreddit_success_selector, 1),
                #("create_subreddit_failed", selectors.create_subreddit_failed_selector, 2),
                #("join_subreddit_success", selectors.join_subreddit_success_selector, 1),
                #("join_subreddit_failed", selectors.join_subreddit_failed_selector, 2),
                #("create_post_success", selectors.create_post_success_selector, 1),
                #("create_post_failed", selectors.create_post_failed_selector, 2),
            ]
}
fn handle_user(
    state: types.UserState,
    msg: types.UserMessage
    ) -> actor.Next(types.UserState, types.UserMessage) {

    case msg {

        types.UserTestMessage -> {

            io.println("[CLIENT]: Entered client sending register user" <> int.to_string(state.id))
            actor.continue(state)
        }

//---------------------------------------------- RegisterUser -------------------------------------------

        types.InjectRegisterUser -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting register user")
            utls.send_to_engine(#("register_user", self(), state.user_name, "test_pwd"))
            actor.continue(state)

        }

        types.RegisterUserFailed -> {

            io.println("User id taken.. try another")
            actor.continue(state)
        }

        types.RegisterUserSuccess(uuid) -> {

            io.println("[CLIENT]: registered client with uuid: " <> uuid)
            let new_state = types.UserState(
                                ..state,
                                uuid: uuid
                            )
            actor.continue(new_state)
        }

//---------------------------------------------- CreateSubReddit ----------------------------------------

        types.InjectCreateSubReddit -> {

            case state.uuid == "" {

                True -> {
                    process.send_after(state.self_sub, 1000, types.InjectCreateSubReddit)
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

        types.CreateSubRedditSuccess(subreddit_name) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully created subreddit " <> subreddit_name)
            actor.continue(state)
        }

        types.CreateSubRedditFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to create subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- JoinSubReddit ------------------------------------------

        types.InjectJoinSubReddit -> {

            case state.uuid == "" {

                True -> {

                    process.send_after(state.self_sub, 2000, types.InjectJoinSubReddit)
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

        types.JoinSubRedditSuccess(subreddit_name) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully joined subreddit " <> subreddit_name)
            actor.continue(state)
        }

        types.JoinSubRedditFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to join subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

//---------------------------------------------- CreatePost -------------------------------------------

        types.InjectCreatePost -> {

            case state.uuid == "" {

                True -> {

                    process.send_after(state.self_sub, 3000, types.InjectCreatePost)
                    Nil
                }

                False -> {

                    let post = types.Post(
                                title: "test title",
                                body: "post_body"
                               )
                    |> decoders.post_serializer
                    io.println("[CLIENT]: " <> int.to_string(state.id) <> " injecting create post")
                    utls.send_to_engine(#("create_post", self(), state.uuid, "test_subreddit_user_1", post))
                    Nil
                }
            }
            actor.continue(state)
        }
        
        types.CreatePostSuccess(subreddit_name) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " successfully posted to subreddit " <> subreddit_name)
            actor.continue(state)
        }

        types.CreatePostFailed(subreddit_name, fail_reason) -> {

            io.println("[CLIENT]: " <> int.to_string(state.id) <> " failed to post to subreddit " <> subreddit_name <> " \n|||| REASON: " <> fail_reason <> " |||\n")
            actor.continue(state)
        }

    }
}
