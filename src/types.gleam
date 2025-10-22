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

    InjectRegisterUser

    InjectCreateSubReddit

    InjectJoinSubReddit

    InjectCreatePost

    SubRedditCreateSuccess(subreddit_name: String)

    SubRedditCreateFailed(subreddit_name: String, fail_reason: String)

    SubRedditJoinSuccess(subreddit_name: String)

    SubRedditJoinFailed(subreddit_name: String, fail_reason: String)

    CreatePostSuccess(subreddit_name: String)

    CreatePostFailed(subreddit_name: String, fail_reason: String)
}

pub type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(UserMessage),
        engine_pid: process.Pid,
        engine_atom: atom.Atom,
        user_name: String,
        uuid: String,
    )
}

pub type Post {

    Post(
        title: String,
        body: String,
    )
}

pub type EngineMessage {

    EngineTestMessage

    RegisterUser(send_pid: process.Pid, username: String, password: String)

    CreateSubReddit(send_pid: process.Pid, uuid: String, subreddit_name: String)

    JoinSubReddit(send_pid: process.Pid, uuid: String, subreddit_name: String)

    CreatePost(send_pid: process.Pid, uuid: String, subreddit_name: String, post: Post)

}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(EngineMessage),
        user_metadata: Dict(String, #(String, BitArray, List(String))),
        user_index: Dict(String, String),
        pidmap: Dict(String, process.Pid),
        subreddit_metadata: Dict(String, #(String, String, String)),
        topicmap: Dict(String, List(String)),
        subreddit_index: Dict(String, String),
        subreddit_posts: Dict(String, List(Post))
    )
}

pub type EngineError {

    SubRedditCreateError(fail_reason: String)
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

            panic as "Failed to parse message register user"
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

pub fn create_subreddit_decoder(
    data: dynamic.Dynamic
    ) -> EngineMessage {

    let res = {

        let pid_decoder = decode.new_primitive_decoder("Pid", pid_decode)
        use send_pid <- result.try(decode.run(data, decode.at([1], pid_decoder)))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, uuid, subreddit_name)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name)) -> {

            CreateSubReddit(send_pid, uuid, subreddit_name)
        } 

        Error(_) -> {

            panic as "illegal value passed to CreateSubReddit"
        }
    }

}

pub fn subreddit_create_success_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            SubRedditCreateSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditCreateSuccess"
        }
    }
}

pub fn subreddit_create_failed_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            SubRedditCreateFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditCreateFailed message"
        }
    }
}

pub fn join_subreddit_decoder(
    data: dynamic.Dynamic
    ) -> EngineMessage {

    let res = {

        let pid_decoder = decode.new_primitive_decoder("Pid", pid_decode)
        use send_pid <- result.try(decode.run(data, decode.at([1], pid_decoder)))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, uuid, subreddit_name)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name)) -> {

            JoinSubReddit(send_pid, uuid, subreddit_name)
        } 

        Error(_) -> {

            panic as "illegal value passed to JoinSubReddit"
        }
    }

}
pub fn subreddit_join_success_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            SubRedditJoinSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditJoinSuccess" 
        }
    }
}

pub fn subreddit_join_failed_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            SubRedditJoinFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditJoinFailed message"
        }
    }
}

pub fn create_post_success_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            CreatePostSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to CreatePostSuccess" 
        }
    }
}

pub fn create_post_failed_decoder(
    data: dynamic.Dynamic
    ) -> UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            CreatePostFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to CreatePostFailed message"
        }
    }
}

pub fn post_serializer(post: Post) -> dynamic.Dynamic {

    dynamic.properties([
        #(dynamic.string("title"), dynamic.string(post.title)),
        #(dynamic.string("body"), dynamic.string(post.body)),
        ])

}

fn post_decoder() -> decode.Decoder(Post) {

    use title <- decode.field("title", decode.string)
    use body <- decode.field("body", decode.string)
    decode.success(Post(title: title, body: body))
}

pub fn create_post_decoder(
    data: dynamic.Dynamic
    ) -> EngineMessage {

    let res = {

        let pid_decoder = decode.new_primitive_decoder("Pid", pid_decode)
        use send_pid <- result.try(decode.run(data, decode.at([1], pid_decoder)))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        use post <- result.try(decode.run(data, decode.at([4], post_decoder())))
        Ok(#(send_pid, uuid, subreddit_name, post)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name, post)) -> {

            CreatePost(send_pid, uuid, subreddit_name, post)
        } 

        Error(_) -> {

            panic as "illegal value passed to JoinSubReddit"
        }
    }

}
