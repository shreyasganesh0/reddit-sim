import gleam/io

import gleam/erlang/process
import gleam/dynamic
import gleam/dynamic/decode

import utls
import generated/generated_types

@external(erlang, "erlang", "is_pid")
fn is_pid(pid: dynamic.Dynamic) -> Bool 

pub fn pid_decoder(_data: dynamic.Dynamic) -> decode.Decoder(process.Pid) { 

    let pid_decode = fn(data) {
        let default_pid = process.spawn_unlinked(fn(){Nil})
        process.kill(default_pid)

         {
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
    }
    decode.new_primitive_decoder("Pid", pid_decode)
}


pub fn post_serializer(post: generated_types.Post) -> dynamic.Dynamic {

    dynamic.properties([
        #(dynamic.string("title"), dynamic.string(post.title)),
        #(dynamic.string("body"), dynamic.string(post.body)),
        ])

}

pub fn post_decoder() -> decode.Decoder(generated_types.Post) {

    use title <- decode.field("title", decode.string)
    use body <- decode.field("body", decode.string)
    decode.success(generated_types.Post(title: title, body: body))
}
