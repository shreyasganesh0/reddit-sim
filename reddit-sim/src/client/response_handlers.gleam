import gleam/io
import gleam/http/response
import gleam/json

import generated/generated_decoders as gen_decode
import generated/generated_types as gen_types

pub type ReplState {

    ReplState(
        user_id: String,
        subreddits: List(String),
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
                subreddits: [subreddit_id, ..state.subreddits]
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
