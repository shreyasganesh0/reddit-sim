import gleam/io
import gleam/int
import gleam/list
import gleam/dynamic/decode
import gleam/dynamic

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process
import gleam/erlang/atom
import gleam/erlang/node

import types
import utls

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic 

@external(erlang, "global", "send")
fn global_send(name: atom.Atom, msg: dynamic.Dynamic) -> process.Pid 

@external(erlang, "erlang", "self")
fn self() -> process.Pid

pub fn create(num_users: Int) -> Nil {

    let main_sub = process.new_subject()
    let engine_atom = atom.create("engine")
    let engine_node = atom.create("engine@localhost")

    let builder = supervisor.new(supervisor.OneForOne)
    let builder = list.range(1, num_users) 
    |> list.fold(builder, fn(acc, a) {
                            let res = start(a, engine_atom, engine_node)
                            supervisor.add(acc, supervision.worker(fn() {res}))
                          }
        )

    let _ = supervisor.start(builder)

    process.receive_forever(main_sub)
    Nil
}

fn start(
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom
    ) -> actor.StartResult(types.UserMessage) {

    actor.new_with_initialiser(100000, fn(sub) {init(sub, id, engine_atom, engine_node)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(types.UserMessage),
    id: Int,
    engine_atom: atom.Atom,
    engine_node: atom.Atom
    ) -> Result(actor.Initialised(types.UserState, types.UserMessage, types.UserMessage), String) {

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
        let pid = case global_whereisname(engine_atom) 
        |> decode.run(decode.new_primitive_decoder("Pid", types.pid_decode))

        {

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
                            user_name: "user_" <> int.to_string(id)
                         )

        let selector = process.new_selector() 
        let selector_tag_list = [
                                #("register_failed", types.register_failed_decoder, 0),
                                #("register_success", types.register_success_decoder, 1),
                                ]

        let selector = utls.create_selector(selector, selector_tag_list)

        let ret = actor.initialised(init_state)
        |> actor.returning(types.UserTestMessage)
        |> actor.selecting(selector)

        global_send(engine_atom, utls.unsafe_coerce(
                                        #("register_user", self(), init_state.user_name, "test_pwd")
                                       )
        )
        Ok(ret)
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

        types.RegisterFailed -> {

            io.println("User id taken.. try another")
            actor.continue(state)
        }

        types.RegisterSuccess(uuid) -> {

            io.println("[CLIENT]: registered client with uuid: " <> uuid)
            actor.continue(state)
        }
    }
}
