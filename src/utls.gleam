import gleam/erlang/process
import gleam/dynamic
import gleam/io

@external(erlang, "erlang", "is_pid")
fn is_pid(pid: dynamic.Dynamic) -> Bool 

@external(erlang, "gleam_stdlib", "identity")
fn unsafe_coerce(a: a) -> b

pub fn pid_decoder(default_pid: process.Pid, data: dynamic.Dynamic) -> Result(process.Pid, process.Pid) {


    case is_pid(data) {

        True -> {

            let pid: process.Pid = unsafe_coerce(data)
            Ok(pid)
        }

        False -> { 
            
            io.println("fail pid check")
            Error(default_pid)
        }
    }
}
