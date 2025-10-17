import gleam/erlang/process
import gleam/dynamic/decode
import gleam/dynamic

@external(erlang, "erlang", "is_pid")
fn is_pid(pid: dynamic.Dynamic) -> Bool 

@external(erlang, "erlang", "list_to_pid")
fn str_to_pid(str: String) -> process.Pid

pub fn pid_decoder(default_pid: process.Pid, data: dynamic.Dynamic) -> Result(process.Pid, process.Pid) {


    case is_pid(data) {

        True -> {

            let assert Ok(str) = decode.run(data, decode.string)
            Ok(str_to_pid(str))
        }

        False -> Error(default_pid)
    }
}
