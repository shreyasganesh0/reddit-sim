import gleam/io
import gleam/int
import gleam/list

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process

type UserMessage {

    TestMessage
}

type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(UserMessage)
    )
}

pub fn create(num_users: Int) -> Nil {

    let builder = supervisor.new(supervisor.OneForOne)
    let builder = list.range(1, num_users) 
    |> list.fold(builder, fn(acc, a) {
                            let res = create_actor(a)
                            supervisor.add(acc, supervision.worker(fn() {res}))
                          }
        )

    let _ = supervisor.start(builder)

    Nil
}

fn create_actor(
    id: Int,
    ) -> actor.StartResult(UserMessage) {

    actor.new_with_initialiser(1000, fn(sub) {init(sub, id)})
    |> actor.on_message(handle_user)
    |> actor.start
}

fn init(
    sub: process.Subject(UserMessage),
    id: Int
    ) -> Result(actor.Initialised(UserState, UserMessage, UserMessage), String) {


        let init_state = UserState(
                            id: id,
                            self_sub: sub
                         )

        let ret = actor.initialised(init_state)
        |> actor.returning(TestMessage)

        process.send(sub, TestMessage)
        Ok(ret)
}

fn handle_user(
    state: UserState,
    msg: UserMessage
    ) -> actor.Next(UserState, UserMessage) {

    case msg {

        TestMessage -> {

            io.println("Entered actor " <> int.to_string(state.id))
            actor.continue(state)
        }
    }
}
