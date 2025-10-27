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


pub type User {

    User(
        id: String,
        username: String,
        passhash: BitArray,
        subreddit_membership_list: List(String),
    )
}

pub type Subreddit {

    Subreddit(
        id: String,
        name: String,
        creator_id: String,
    )
}

pub type EngineState {

    EngineState(
        self_sub: process.Subject(gen_types.EngineMessage),
        users_data: Dict(String, User),
        user_rev_index: Dict(String, String),
        user_pid_map: Dict(String, process.Pid),
        subreddits_data: Dict(String, Subreddit),
        subreddit_users_map: Dict(String, List(String)),
        subreddit_rev_index: Dict(String, String),
        subreddit_posts_map: Dict(String, List(gen_types.Post)),
        parent_comment_map: Dict(String, String),
        comments_data: Dict(String, gen_types.Comment)
    )
}

