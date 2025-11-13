import gleam/io
import gleam/http/response
import gleam/json
import gleam/dict.{type Dict}

import generated/generated_decoders as gen_decode
import generated/generated_types as gen_types

pub type ReplState {

    ReplState(
        user_id: String,
        subreddits: List(String),
        to_update_subreddit_name: String,
        subreddit_rev_index: Dict(String, String)
    )
}

pub fn register_user(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_register_user_success_decoder()) {

        Ok(gen_types.RestRegisterUserSuccess(user_id)) -> {

            io.println("[CLIENT]: registered with id "<>user_id)
            ReplState(
                ..state,
                user_id: user_id,
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn login_user(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_login_user_success_decoder()) {

        Ok(gen_types.RestLoginUserSuccess(user_id)) -> {

            io.println("[CLIENT]: login with id "<>user_id)
            ReplState(
                ..state,
                user_id: user_id,
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn create_subreddit(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_create_subreddit_success_decoder()) {

        Ok(gen_types.RestCreateSubredditSuccess(subreddit_id)) -> {

            io.println("[CLIENT]: created subreddit with id "<>subreddit_id)
            ReplState(
                ..state,
                subreddits: [subreddit_id, ..state.subreddits],
                subreddit_rev_index: dict.insert(
                    state.subreddit_rev_index,
                    state.to_update_subreddit_name,
                    subreddit_id
                ),
                to_update_subreddit_name: "",
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn join_subreddit(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_join_subreddit_success_decoder()) {

        Ok(gen_types.RestJoinSubredditSuccess(subreddit_id)) -> {

            io.println("[CLIENT]: join subreddit with id "<>subreddit_id)
            ReplState(
                ..state,
                subreddits: [subreddit_id, ..state.subreddits],
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn leave_subreddit(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_leave_subreddit_success_decoder()) {

        Ok(gen_types.RestLeaveSubredditSuccess(subreddit_id)) -> {

            io.println("[CLIENT]: left subreddit with id "<>subreddit_id)
            state
        }

        _ -> {

            state
        }
    }
    
}

pub fn search_subreddit(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_search_subreddit_success_decoder()) {

        Ok(gen_types.RestSearchSubredditSuccess(subreddit_id)) -> {

            io.println("[CLIENT]: found subreddit with id "<>subreddit_id)
            ReplState(
                ..state,
                subreddits: [subreddit_id, ..state.subreddits],
                subreddit_rev_index: dict.insert(
                    state.subreddit_rev_index,
                    state.to_update_subreddit_name,
                    subreddit_id
                ),
                to_update_subreddit_name: "",
            )
        }

        _ -> {

            state
        }
    }
    
}
pub fn logout(_resp: response.Response(BitArray), state: ReplState) -> ReplState {

    io.println("[CLIENT]: logged out")
    ReplState(
        ..state,
        user_id: "",
    )
    
}
