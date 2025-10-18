import gleam/erlang/process
import gleam/dynamic
import gleam/list

@external(erlang, "gleam_stdlib", "identity")
pub fn unsafe_coerce(a: a) -> b

@external(erlang, "erlang", "send")
pub fn pid_send(pid: process.Pid, msg: dynamic.Dynamic) -> dynamic.Dynamic 

pub fn create_selector(
    selector: process.Selector(payload),
    selector_tags: List(#(String, fn(dynamic.Dynamic) -> payload, Int))
    ) -> process.Selector(payload) {


        list.fold(selector_tags, selector, fn(acc, a) {

                                               let #(tag, decoder, arity) = a
                                               process.select_record(acc, tag, arity, decoder)
                                           }
        )
}
