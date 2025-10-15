import gleam/dict.{type Dict}

import gleam/erlang/process

pub type UserMessage {

    UserTestMessage

    RegisterFailed

    RegisterSuccess(uuid: String)
}

pub type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(UserMessage)
    )
}

pub type EngineMessage {

    EngineTestMessage

    RegisterUser(send_sub: process.Subject(UserMessage), username: String, password: String)
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(EngineMessage),
        usermap: Dict(String, #(String, BitArray))
    )
}
