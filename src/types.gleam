import gleam/dict.{type Dict}

import gleam/erlang/process
import gleam/erlang/atom

pub type UserMessage {

    UserTestMessage

    RegisterUserFailed

    RegisterUserSuccess(uuid: String)

    InjectRegisterUser

    InjectCreateSubReddit

    InjectJoinSubReddit

    InjectCreatePost

    CreateSubRedditSuccess(subreddit_name: String)

    CreateSubRedditFailed(subreddit_name: String, fail_reason: String)

    JoinSubRedditSuccess(subreddit_name: String)

    JoinSubRedditFailed(subreddit_name: String, fail_reason: String)

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

pub type UserMetaData {

    UserMetaData(
        username: String,
        passhash: BitArray,
        subreddit_membership_list: List(String),
    )
}

pub type SubRedditMetaData {

    SubRedditMetaData(
        name: String,
        creator_id: String,
    )
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(EngineMessage),
        user_metadata: Dict(String, UserMetaData),
        user_index: Dict(String, String),
        pidmap: Dict(String, process.Pid),
        subreddit_metadata: Dict(String, SubRedditMetaData),
        topicmap: Dict(String, List(String)),
        subreddit_index: Dict(String, String),
        subreddit_posts: Dict(String, List(Post))
    )
}

