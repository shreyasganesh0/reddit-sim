import gleam/io
import gleam/int
import gleam/string
import gleam/http/response
import gleam/json
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/bit_array
import gleam/erlang/process

import rsa_keys
import utls

import client/request_builders
import client/client_sse

import generated/generated_decoders as gen_decode
import generated/generated_types as gen_types

pub type ReplState {

    ReplState(
        user_id: String,
        user_name: String,
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
        priv_key: String,
        pub_key: String,
        pub_key_map: Dict(String, String),
        posts_data: Dict(String, gen_types.Post),
        signature: String
    )
}

pub fn register_user(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_register_user_success_decoder()) {

        Ok(gen_types.RestRegisterUserSuccess(user_id)) -> {

            case rsa_keys.sign_message_with_pem_string(bit_array.from_string(user_id), state.priv_key) {

                Ok(sig) -> {

                    io.println("[CLIENT]: registered with id "<>user_id)
                    ReplState(
                        ..state,
                        user_id: user_id,
                        signature: sig|>bit_array.base16_encode
                    )
                }

                Error(_) -> {
                    io.println("[CLIENT]: failed to sign id, register again"<>user_id)
                    state
                }
            } 
        }

        _ -> {

            state
        }
    }
    
}

pub fn login_user(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_login_user_success_decoder()) {

        Ok(gen_types.RestLoginUserSuccess(user_id)) -> {

            case rsa_keys.sign_message_with_pem_string(bit_array.from_string(user_id), state.priv_key) {

                Ok(sig) -> {

                    io.println("[CLIENT]: registered with id "<>user_id)
                    ReplState(
                        ..state,
                        user_id: user_id,
                        signature: sig|>bit_array.base16_encode
                    )
                }

                Error(_) -> {
                    io.println("[CLIENT]: failed to sign id, register again"<>user_id)
                    state
                }
            } 
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

        Ok(gen_types.RestSearchUserSuccess(user_id, pub_key)) -> {

            io.println("[CLIENT]: found user with id "<>user_id<>" pub_key: " <> pub_key)
            ReplState(
                ..state,
                users: [user_id, ..state.users],
                user_rev_index: dict.insert(
                    state.user_rev_index,
                    state.to_update_user_name,
                    user_id
                ),
                pub_key_map: dict.insert(
                    state.pub_key_map,
                    user_id,
                    pub_key,
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

            case verify_post(post, state) {

                Ok(_) -> {

                    io.println("[CLIENT]: got post with id "<>post.id)
                    display_post(post, comments)
                    ReplState(
                        ..state,
                        posts_data: dict.insert(state.posts_data, post.id, post)
                    )
                }

                Error(err) -> {

                    case err {
                        SignatureDecodeFail -> {

                            io.println(
                                "[CLIENT]: couldnt decode signature from post with owner: "
                                <>post.owner_name
                            )

                        }

                        PubkeyNotExists -> {

                    io.println("[CLIENT]: couldnt find pub key for user: "<>post.owner_name<>" try searching for them using search-user <username>")
                        }

                        VerifyRuntimeError(err) -> {

                    io.println("[CLIENT]: invalid public key format: "<> err <>"try searching for them using search-user: "<>post.owner_name)
                        }

                        UnalbetoVerifySignature -> {

                    io.println("[CLIENT]: couldnt verify post with owners pub key: "<>post.owner_name)
                        }
                    }
                    io.println("[CLIENT]: couldnt verify post owner")
                    state
                }
            }

        }

        _ -> {

            state
        }
    }
    
}

pub fn create_comment(resp: response.Response(BitArray), state: ReplState) -> ReplState {

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

    case json.parse_bits(resp.body, gen_decode.rest_get_feed_success_decoder()) {

        Ok(gen_types.RestGetFeedSuccess(posts_list)) -> {

            io.println("[CLIENT]: got feed of posts")
            list.fold(
                posts_list,
                state,
                fn(state, post) {

                    case verify_post(post, state) {

                        Ok(_) -> {

                            display_post(post, [])
                            ReplState(
                                ..state,
                                subreddits: [post.subreddit_id, ..state.subreddits],
                                posts_data: dict.insert(
                                                state.posts_data,
                                                post.id,
                                                post
                                            )
                            )
                        }

                        Error(err) -> {

                            case err {

                                SignatureDecodeFail -> {

                                    io.println(
                                        "[CLIENT]: couldnt decode signature from post with owner: "
                                        <>post.owner_name
                                    )

                                }

                                PubkeyNotExists -> {

                            io.println("[CLIENT]: couldnt find pub key for user: "<>post.owner_name<>" try searching for them using search-user <username>")
                                }

                                VerifyRuntimeError(err) -> {

                            io.println("[CLIENT]: invalid public key format: "<> err <>"try searching for them using search-user: "<>post.owner_name)
                                }

                                UnalbetoVerifySignature -> {

                            io.println("[CLIENT]: couldnt verify post with owners pub key: "<>post.owner_name)
                                }
                            }
                            state
                        }
                    }
                }
            )
        }

        _ -> {

            state
        }
    }
}

pub fn get_subredditfeed(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_get_subredditfeed_success_decoder()) {

        Ok(gen_types.RestGetSubredditfeedSuccess(posts_list)) -> {

            io.println("[CLIENT]: got subreddit feed of posts")

            list.fold(
                posts_list,
                state,
                fn(state, post) {

                    case verify_post(post, state) {

                        Ok(_) -> {

                            display_post(post, [])
                            ReplState(
                                ..state,
                                subreddits: [post.subreddit_id, ..state.subreddits],
                                posts_data: dict.insert(
                                                state.posts_data,
                                                post.id,
                                                post
                                            )
                            )
                        }

                        Error(err) -> {

                            case err {
                                SignatureDecodeFail -> {

                                    io.println(
                                        "[CLIENT]: couldnt decode signature from post with owner: "
                                        <>post.owner_name
                                    )

                                }

                                PubkeyNotExists -> {

                            io.println("[CLIENT]: couldnt find pub key for user: "<>post.owner_name<>" try searching for them using search-user <username>")
                                }

                                VerifyRuntimeError(err) -> {

                            io.println("[CLIENT]: invalid public key format: "<> err <>"try searching for them using search-user: "<>post.owner_name)
                                }

                                UnalbetoVerifySignature -> {

                            io.println("[CLIENT]: couldnt verify post with owners pub key: "<>post.owner_name)
                                }
                            }
                            state
                        }
                    }
                }
            )
        }

        _ -> {

            state
        }
    }
}

pub fn start_directmessage(resp: response.Response(BitArray), state: ReplState) -> ReplState {

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

pub fn reply_directmessage(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_reply_directmessage_success_decoder()) {

        Ok(gen_types.RestReplyDirectmessageSuccess(dm_id)) -> {

            io.println("[CLIENT]: reply dm with dm id: "<> dm_id)
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

pub fn get_directmessages(resp: response.Response(BitArray), state: ReplState) -> ReplState {

    case json.parse_bits(resp.body, gen_decode.rest_get_directmessages_success_decoder()) {

        Ok(gen_types.RestGetDirectmessagesSuccess(dms)) -> {


            io.println("[CLIENT]: got dms")
            list.each(dms, print_dm)
            let new_state = ReplState(
                ..state,
                user_dm_map: list.fold(
                    dms, 
                    state.user_dm_map,
                    fn(user_dict, dm) {
                        list.fold(
                            dm.participants,
                            user_dict, 
                            fn(acc, user_id) {
                                case user_id != state.user_id {

                                    True -> dict.insert(acc, user_id, dm.id)

                                    False -> acc
                                }
                            }
                        )
                    }
                ),
                user_rev_index: list.fold(
                    dms,
                    state.user_rev_index,
                    fn(user_rev_idx, dm) {

                        list.zip(dm.usernames, dm.participants)
                        |> list.fold(
                            user_rev_idx, 
                            fn(acc, user) {
                                let #(curr_name, curr_id) = user
                                case curr_id != state.user_id {

                                    True -> dict.insert(acc, curr_name, curr_id)

                                    False -> acc
                                }
                            }
                        )
                    }
                )
            )

            new_state
        }

        _ -> {

            state
        }
    }
}

pub fn register_notifications(_resp: response.Response(BitArray), state: ReplState) -> ReplState {

    let req = request_builders.register_notifications(state.user_id, state.signature)

    process.spawn(fn(){
        let _ = client_sse.start(req)
        process.sleep_forever()
        })

    state
}

pub fn help(_resp: response.Response(BitArray), state: ReplState) -> ReplState {

    io.println("\n--- AVAILABLE COMMANDS ---")
    
    io.println("Authentication:")
    io.println("  register <username> <password>")
    io.println("  login <username> <password>")
    io.println("  logout")

    io.println("\nUser & System:")
    io.println("  search-user <username>")
    io.println("  notifications")

    io.println("\nSubreddits:")
    io.println("  create-subreddit <subreddit_name>")
    io.println("  join-subreddit <subreddit_name>")
    io.println("  leave-subreddit <subreddit_name>")
    io.println("  search-subreddit <subreddit_name>")
    io.println("  get-subredditfeed <subreddit_name>")

    io.println("\nPosts:")
    io.println("  create-post --subreddit-name <name> --title <title> --body <body>")
    io.println("  repost <post_id>")
    io.println("  get-post <post_id>")
    io.println("  delete-post <post_id>")
    io.println("  get-feed")

    io.println("\nInteraction:")
    io.println("  create-comment --parent-id <post_or_comment_id> --body <body>")
    io.println("  upvote <parent_id>")
    io.println("  downvote <parent_id>")
    io.println("  unvote <parent_id>")

    io.println("\nDirect Messages:")
    io.println("  send-dm --to <username> --message <message>")
    io.println("  reply-dm --to <username> --message <message>")
    io.println("  get-dms")
    
    io.println("--------------------------\n")

    state
}
type VerifyError {

    SignatureDecodeFail

    PubkeyNotExists

    VerifyRuntimeError(err: String)

    UnalbetoVerifySignature
}


fn verify_post(post: gen_types.Post, state: ReplState) {

    let msg = utls.get_post_ser(post) 
    use sig_bits <- result.try(
        result.map_error(
        bit_array.base16_decode(post.signature),
        fn(_) {SignatureDecodeFail}
        )
    )
    use pub_key <- result.try(
        result.map_error(
            dict.get(state.pub_key_map, post.owner_id),
            fn(_) {PubkeyNotExists}
        )
    )
    use verify <- result.try(
        result.map_error(
        rsa_keys.verify_message_with_pem_string(msg, pub_key, sig_bits),
        fn(err) {VerifyRuntimeError(err)}
        )
    )
    case verify {

        True -> Ok(Nil)

        False -> Error(UnalbetoVerifySignature)
    }
}

fn print_post(post: gen_types.Post) {
    let votes = int.to_string(post.upvotes - post.downvotes)
  
    io.println("\n================ [ POST ] ================")
    io.println("TITLE:    " <> post.title)
    io.println("ID:       " <> post.id) 
    io.println("AUTHOR:   " <> post.owner_name <> " (ID: " <> post.owner_id <> ")")
    io.println("SUBREDDIT:" <> post.subreddit_id)
    io.println("SCORE:    " <> votes <> " (+" <> int.to_string(post.upvotes) <> "|-" <> int.to_string(post.downvotes) <> ")")
    io.println("------------------------------------------")
    io.println(post.body)
    io.println("==========================================\n")
}

fn print_comment(comment: gen_types.Comment) {

    let votes = int.to_string(comment.upvotes - comment.downvotes)

    io.println("\n---------------- [ COMMENT ] ---------------")
    io.println("ID:       " <> comment.id) 

    io.println("AUTHOR ID:" <> comment.owner_id) 
    io.println("PARENT ID:" <> comment.parent_id)

    io.println("SCORE:    " <> votes <> " (+" <> int.to_string(comment.upvotes) <> "|-" <> int.to_string(comment.downvotes) <> ")")
    io.println("BODY:")
    io.println("\t" <> comment.body)
    io.println("--------------------------------------------\n")
} 

fn print_dm(dm: gen_types.Dm) {

    let participants_str = list.zip(dm.usernames, dm.participants)
    |> list.map(fn(pair) {
      let #(name, id) = pair
      name <> " (" <> id <> ")"
    })
    |> string.join(", ")

    io.println("\n================ [ DM ] ==================")
    io.println("DM ID:        " <> dm.id)
    io.println("PARTICIPANTS: " <> participants_str)
    io.println("------------------------------------------")
    io.println("MESSAGES:")

    list.each(dm.msgs_list, fn(msg) {
    io.println(" > " <> msg)
    })
    io.println("==========================================\n")
}

fn display_post(post: gen_types.Post, comments: List(gen_types.Comment)) {

    print_post(post)
    case list.length(comments) {

        0 -> {Nil}

        _ -> {
            io.println("COMMENTS:\n")
            list.each(comments, print_comment)
        }
    }
}
