import gleam/io

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision 

import gleam/erlang/process

import types 

pub fn create() -> Nil {

    let _ = supervisor.new(supervisor.OneForOne)
    |> supervisor.add(supervision.worker(fn() {start()}))
    |> supervisor.start

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
                     )

    let ret = actor.initialised(init_state)
    |> actor.returning(types.EngineTestMessage)

    process.send(sub, types.EngineTestMessage)

    Ok(ret)
}

fn handle_engine(
    state: types.EngineState,
    msg: types.EngineMessage,
    ) -> actor.Next(types.EngineState, types.EngineMessage) {

    case msg {

        types.EngineTestMessage -> {

            io.println("Started types.Engine...")
            actor.continue(state)
        }
    }
}
