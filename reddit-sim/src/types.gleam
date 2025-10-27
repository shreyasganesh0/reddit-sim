import gleam/dict.{type Dict}

import gleam/erlang/process
import gleam/erlang/atom
import generated/generated_types as gen_types


pub type UserState {

    UserState(
        id: Int,
        self_sub: process.Subject(gen_types.UserMessage),
        engine_pid: process.Pid,
        engine_atom: atom.Atom,
        user_name: String,
        uuid: String,
    )
}


pub type UserMetaData {

    UserMetaData(
        username: String,
        passhash: BitArray,
        subreddit_membership_list: List(String),
    )
}

pub type SubredditMetaData {

    SubredditMetaData(
        name: String,
        creator_id: String,
    )
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(gen_types.EngineMessage),
        user_metadata: Dict(String, UserMetaData),
        user_index: Dict(String, String),
        pidmap: Dict(String, process.Pid),
        subreddit_metadata: Dict(String, SubredditMetaData),
        topicmap: Dict(String, List(String)),
        subreddit_index: Dict(String, String),
        subreddit_posts: Dict(String, List(gen_types.Post))
    )
}

