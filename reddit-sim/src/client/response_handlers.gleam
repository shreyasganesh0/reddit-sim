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
