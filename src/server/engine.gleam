import gleam/io
import gleam/dict
import gleam/crypto
import gleam/bit_array
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
    let selector_tag_list = [#("register_user", types.register_user_decoder, 3)]

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
                                                    username,
                                                    #(uid, passhash),
                                                 )
                                    )
                    utls.send_to_pid(send_pid, #("register_success", uid))
                    actor.continue(new_state)
                }
            }
        }
    }
}
