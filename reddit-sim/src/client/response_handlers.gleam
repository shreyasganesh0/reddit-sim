import gleam/io
import gleam/http/response
import gleam/json
import gleam/dict.{type Dict}
import gleam/list

import generated/generated_decoders as gen_decode
import generated/generated_types as gen_types

pub type ReplState {

    ReplState(
        user_id: String,
        subreddits: List(String),
        to_update_subreddit_name: String,
        subreddit_rev_index: Dict(String, String),
        posts: List(String),
        comments: List(String),
        users: List(String),
        to_update_user_name: String,
        user_rev_index: Dict(String, String),
        user_dm_map: Dict(String, String),
        to_update_user_dm: String,
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

pub fn search_user(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_search_user_success_decoder()) {

        Ok(gen_types.RestSearchUserSuccess(user_id)) -> {

            io.println("[CLIENT]: found user with id "<>user_id)
            ReplState(
                ..state,
                users: [user_id, ..state.users],
                user_rev_index: dict.insert(
                    state.user_rev_index,
                    state.to_update_user_name,
                    user_id
                ),
                to_update_user_name: "",
            )
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

pub fn create_post(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_create_post_success_decoder()) {

        Ok(gen_types.RestCreatePostSuccess(post_id)) -> {

            io.println("[CLIENT]: created post with id "<>post_id)
            ReplState(
                ..state,
                posts: [post_id, ..state.posts]
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn create_repost(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_create_repost_success_decoder()) {

        Ok(gen_types.RestCreateRepostSuccess(post_id)) -> {

            io.println("[CLIENT]: created repost with id "<>post_id)
            ReplState(
                ..state,
                posts: [post_id, ..state.posts]
            )
        }

        _ -> {

            state
        }
    }
}

pub fn delete_post(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_delete_post_success_decoder()) {

        Ok(gen_types.RestDeletePostSuccess(post_id)) -> {

            io.println("[CLIENT]: deleted post with id "<>post_id)
            ReplState(
                ..state,
                posts: list.drop_while(
                    state.posts,
                    fn(a) {a == post_id}
                )
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn get_post(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_get_post_success_decoder()) {

        Ok(gen_types.RestGetPostSuccess(post, comments)) -> {

            io.println("[CLIENT]: created repost with id "<>post.id)
            echo post
            echo comments
            ReplState(
                ..state,
                posts: [post.id, ..state.posts]
            )
        }

        _ -> {

            state
        }
    }
    
}

pub fn create_comment(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    echo resp
    case json.parse_bits(resp.body, gen_decode.rest_create_comment_success_decoder()) {

        Ok(gen_types.RestCreateCommentSuccess(comment_id)) -> {

            io.println("[CLIENT]: created comment with id "<>comment_id)
            ReplState(
                ..state,
                comments: [comment_id, ..state.comments]
            )
        }

        _ -> {

            state
        }
    }
}

pub fn create_vote(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    echo resp
    case json.parse_bits(resp.body, gen_decode.rest_create_vote_success_decoder()) {

        Ok(gen_types.RestCreateVoteSuccess(comment_id)) -> {

            io.println("[CLIENT]: voted on comment with id "<>comment_id)
            state
        }

        _ -> {

            state
        }
    }
}

pub fn get_feed(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    echo resp
    case json.parse_bits(resp.body, gen_decode.rest_get_feed_success_decoder()) {

        Ok(gen_types.RestGetFeedSuccess(posts_list)) -> {

            io.println("[CLIENT]: got feed of posts")
            ReplState(
                ..state,
                subreddits: list.fold(
                                posts_list,
                                state.subreddits,
                                fn(acc, a) {
                                    [a.id, ..acc]
                                }
                            )
            )
        }

        _ -> {

            state
        }
    }
}

pub fn get_subredditfeed(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    echo resp
    case json.parse_bits(resp.body, gen_decode.rest_get_subredditfeed_success_decoder()) {

        Ok(gen_types.RestGetSubredditfeedSuccess(posts_list)) -> {

            io.println("[CLIENT]: got subreddit feed of posts")
            ReplState(
                ..state,
                subreddits: list.fold(
                                posts_list,
                                state.subreddits,
                                fn(acc, a) {
                                    [a.id, ..acc]
                                }
                            )
            )
        }

        _ -> {

            state
        }
    }
}

pub fn start_directmessage(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    echo resp
    case json.parse_bits(resp.body, gen_decode.rest_start_directmessage_success_decoder()) {

        Ok(gen_types.RestStartDirectmessageSuccess(dm_id)) -> {

            io.println("[CLIENT]: started dm with dm id: "<> dm_id)
            ReplState(
                ..state,
                user_dm_map: dict.insert(
                    state.user_dm_map,
                    state.to_update_user_dm,
                    dm_id
                ),
                to_update_user_dm: ""
            )
        }

        _ -> {

            state
        }
    }
}
