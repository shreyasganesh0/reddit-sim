import gleam/dict.{type Dict}

import gleam/io
import gleam/result
import gleam/dynamic
import gleam/dynamic/decode

import gleam/erlang/process
import gleam/erlang/atom

import utls

pub type UserMessage {

    UserTestMessage

    RegisterFailed

    RegisterSuccess(uuid: String)
}

pub type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(UserMessage),
        engine_pid: process.Pid,
        engine_atom: atom.Atom,
        user_name: String
    )
}

pub type EngineMessage {

    EngineTestMessage

    RegisterUser(send_pid: process.Pid, username: String, password: String)
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(EngineMessage),
        usermap: Dict(String, #(String, BitArray))
    )
}


@external(erlang, "erlang", "is_pid")
fn is_pid(pid: dynamic.Dynamic) -> Bool 

pub fn pid_decode(data: dynamic.Dynamic) -> Result(process.Pid, process.Pid) {

    let default_pid = process.spawn_unlinked(fn(){Nil})
    process.kill(default_pid)

    case is_pid(data) {

        True -> {

            let pid: process.Pid = utls.unsafe_coerce(data)
            Ok(pid)
        }

        False -> { 
            
            io.println("fail pid check")
            Error(default_pid)
        }
    }
}


pub fn register_user_decoder(
    data: dynamic.Dynamic
    ) -> EngineMessage {

    let res = {

        let pid_decoder = decode.new_primitive_decoder("Pid", pid_decode)
        use send_pid <- result.try(decode.run(data, decode.at([1], pid_decoder)))
        use username <- result.try(decode.run(data, decode.at([2], decode.string)))
        use password <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, username, password)) 
    }

    case res {

        Ok(#(send_pid, username, password)) -> {

            RegisterUser(send_pid, username, password)
        }

        Error(_) -> {

            io.println("Failed to parse message register user")
            panic as "will have to pass some value if this actually gets handled by on_message"
        }
    }
}

pub fn register_failed_decoder(
    _data: dynamic.Dynamic,
    ) -> UserMessage {

    RegisterFailed
}

pub fn register_success_decoder(
    data: dynamic.Dynamic,
    ) -> UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(uid) -> {

            RegisterSuccess(uid)
        }

        Error(_) -> {

            panic as "illegal value passed to RegisterSuccess message"
        }
    }
}
