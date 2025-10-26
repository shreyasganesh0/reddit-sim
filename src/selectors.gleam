import gleam/result
import gleam/dynamic
import gleam/dynamic/decode

import types
import decoders

//------------------------------------- RegisterUser ---------------------------------------------------

pub fn register_user_selector(
    data: dynamic.Dynamic
    ) -> types.EngineMessage {

    let res = {

        use send_pid <- result.try(decode.run(data, decode.at([1], decoders.pid_decoder(data))))
        use username <- result.try(decode.run(data, decode.at([2], decode.string)))
        use password <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, username, password)) 
    }

    case res {

        Ok(#(send_pid, username, password)) -> {

            types.RegisterUser(send_pid, username, password)
        }

        Error(_) -> {

            panic as "Failed to parse message register user"
        }
    }
}

pub fn register_user_failed_selector(
    data: dynamic.Dynamic,
    ) -> types.UserMessage {

    let res = {

        use name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(name, fail_reason))
    }

    case res {

        Ok(#(name, fail_reason)) -> {

            types.RegisterUserFailed(name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditCreateFailed message"
        }
    }
}

pub fn register_user_success_selector(
    data: dynamic.Dynamic,
    ) -> types.UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(uid) -> {

            types.RegisterUserSuccess(uid)
        }

        Error(_) -> {

            panic as "illegal value passed to RegisterSuccess message"
        }
    }
}

//------------------------------------- CreateSubReddit -------------------------------------------------

pub fn create_subreddit_selector(
    data: dynamic.Dynamic
    ) -> types.EngineMessage {

    let res = {

        use send_pid <- result.try(decode.run(data, decode.at([1], decoders.pid_decoder(data))))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, uuid, subreddit_name)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name)) -> {

            types.CreateSubReddit(send_pid, uuid, subreddit_name)
        } 

        Error(_) -> {

            panic as "illegal value passed to CreateSubReddit"
        }
    }

}

pub fn create_subreddit_success_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            types.CreateSubRedditSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditCreateSuccess"
        }
    }
}

pub fn create_subreddit_failed_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            types.CreateSubRedditFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditCreateFailed message"
        }
    }
}

//------------------------------------- JoinSubReddit ---------------------------------------------------

pub fn join_subreddit_selector(
    data: dynamic.Dynamic
    ) -> types.EngineMessage {

    let res = {

        use send_pid <- result.try(decode.run(data, decode.at([1], decoders.pid_decoder(data))))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        Ok(#(send_pid, uuid, subreddit_name)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name)) -> {

            types.JoinSubReddit(send_pid, uuid, subreddit_name)
        } 

        Error(_) -> {

            panic as "illegal value passed to JoinSubReddit"
        }
    }

}

pub fn join_subreddit_success_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            types.JoinSubRedditSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditJoinSuccess" 
        }
    }
}

pub fn join_subreddit_failed_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            types.JoinSubRedditFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to SubRedditJoinFailed message"
        }
    }
}

//------------------------------------- CreatePost ---------------------------------------------------

pub fn create_post_selector(
    data: dynamic.Dynamic
    ) -> types.EngineMessage {

    let res = {

        use send_pid <- result.try(decode.run(data, decode.at([1], decoders.pid_decoder(data))))
        use uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
        use subreddit_name <- result.try(decode.run(data, decode.at([3], decode.string)))
        use post <- result.try(decode.run(data, decode.at([4], decoders.post_decoder())))
        Ok(#(send_pid, uuid, subreddit_name, post)) 
    }

    case res {

        Ok(#(send_pid, uuid, subreddit_name, post)) -> {

            types.CreatePost(send_pid, uuid, subreddit_name, post)
        } 

        Error(_) -> {

            panic as "illegal value passed to CreatePost"
        }
    }

}

pub fn create_post_success_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    case decode.run(data, decode.at([1], decode.string)) {

        Ok(name) -> {

            types.CreatePostSuccess(name)
        }

        Error(_) -> {

            panic as "illegal value passed to CreatePostSuccess" 
        }
    }
}

pub fn create_post_failed_selector(
    data: dynamic.Dynamic
    ) -> types.UserMessage {

    let res = {

        use subreddit_name <- result.try(decode.run(data, decode.at([1], decode.string)))
        use fail_reason <- result.try(decode.run(data, decode.at([2], decode.string)))
        Ok(#(subreddit_name, fail_reason))
    }

    case res {

        Ok(#(subreddit_name, fail_reason)) -> {

            types.CreatePostFailed(subreddit_name, fail_reason)
        }

        Error(_) -> {

            panic as "illegal value passed to CreatePostFailed message"
        }
    }
}

