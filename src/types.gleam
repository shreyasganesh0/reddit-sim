import gleam/erlang/process

pub type UserMessage {

    UserTestMessage
}

pub type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(UserMessage)
    )
}

pub type EngineMessage {

    EngineTestMessage
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(EngineMessage)
    )
}
