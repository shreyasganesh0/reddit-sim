import gleam/io
import gleam/int
import gleam/list

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process

import types

pub fn create(num_users: Int) -> Nil {

    let builder = supervisor.new(supervisor.OneForOne)
    let builder = list.range(1, num_users) 
    |> list.fold(builder, fn(acc, a) {
                            let res = start(a)
                            supervisor.add(acc, supervision.worker(fn() {res}))
                          }
        )

    let _ = supervisor.start(builder)

    Nil
}

fn start(
    id: Int,
    ) -> actor.StartResult(types.UserMessage) {

    actor.new_with_initialiser(1000, fn(sub) {init(sub, id)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(types.UserMessage),
    id: Int
    ) -> Result(actor.Initialised(types.UserState, types.UserMessage, types.UserMessage), String) {


        let init_state = types.UserState(
                            id: id,
                            self_sub: sub
                         )

        let ret = actor.initialised(init_state)
        |> actor.returning(types.UserTestMessage)

        process.send(sub, types.UserTestMessage)
        Ok(ret)
}

fn handle_user(
    state: types.UserState,
    msg: types.UserMessage
    ) -> actor.Next(types.UserState, types.UserMessage) {

    case msg {

        types.UserTestMessage -> {

            io.println("Entered client " <> int.to_string(state.id))
            actor.continue(state)
        }
    }
}
