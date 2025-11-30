import in
import gleam/io
import gleam/string
import gleam/result
import gleam/bit_array
import gleam/dict
import gleam/list

import gleam/http/request
import gleam/http/response
import gleam/httpc
import rsa_keys

import utls
import argv

import generated/generated_types as gen_types

import client/response_handlers
import client/request_builders

type ReplError {

    CommandError

    ReadError(in.Error)

    RequestError(httpc.HttpError)

    UnregisteredError

    SubredditUnknownError

    InvalidParentError

    UserUnknownError

    DmExistsError(dm_id: String)

    DmNotExistsError

    SignPostFailedError(err: String)
    
    SignIdFailError(err: String)
    
    PostDoesntExistError
}


fn start_repl(state: response_handlers.ReplState) {

    io.println("[CLIENT]: enter command...")
    let res = {

        use line <- result.try(result.map_error(in.read_line(), fn(e) {ReadError(e)}))
        let line = string.trim(line)
        case line {

            "logout"-> {

                Ok(
                #(response.new(200)|>response.map(bit_array.from_string),
                response_handlers.logout,
                state)
                )
            }

            "help" -> {

                Ok(
                #(response.new(200)|>response.map(bit_array.from_string),
                response_handlers.help,
                state)
                )
            }

            "notifications" -> {

                    Ok(
                        #(
                        response.new(200)|>response.map(bit_array.from_string),
                        response_handlers.register_notifications,
                        state
                        )
                    )
            }

            _ -> {

                use #(req, resp_handler, state) <- result.try(parse_line(line, state))
                use resp <- result.try(
                    result.map_error(
                        httpc.configure()
                        |> httpc.verify_tls(False)
                        |> httpc.dispatch_bits(req),
                        fn(e) {RequestError(e)}
                    )
                )
                Ok(#(resp, resp_handler, state))
            }
        }
    }

    let new_state = case res {

        Ok(#(resp, resp_handler, state)) -> {

            resp_handler(resp, state)
        }
        
        Error(e) -> {

            case e {

                CommandError -> {

                    io.println("Invalid command type \"help\" to see available commands")
                }
                
                ReadError(_) -> {

                    io.println("Invalid command type \"help\" to see available commands")
                }

                RequestError(_) -> {

                    io.println("[CLIENT]: couldnt send request")
                }

                UnregisteredError -> {

                    io.println("[CLIENT]: must be registered/loggedin before performing this command")
                }

                SubredditUnknownError -> {

                    io.println("[CLIENT]: subreddit not found, try searching for it first")
                }

                UserUnknownError -> {

                    io.println("[CLIENT]: user not found, try searching for them first")
                }

                DmExistsError(dm_id) -> {

                    io.println("[CLIENT]: dm exists with id: "<>dm_id<>" use reply-dm instead" )
                }

                DmNotExistsError -> {

                    io.println("[CLIENT]: dm does not exist use send-dm to start a new dm" )
                }

                InvalidParentError -> {

                    io.println("[CLIENT]: id was not a post or comment you know, try searching for it first")
                }

                SignPostFailedError(err) -> {

                    io.println("[CLIENT]: failed to create a valid signature for post: "<> err)
                }
                
                SignIdFailError(err) -> {

                    io.println("[CLIENT]: failed to create a valid signature for id: "<> err)
                }
                PostDoesntExistError -> {

                    io.println("[CLIENT]: trying to repost invaild post id")
                }
            }

            state
        }
    }

    start_repl(new_state)
}

fn parse_line(line: String, state: response_handlers.ReplState) -> Result(
    #(
        request.Request(BitArray),
        fn(response.Response(BitArray), response_handlers.ReplState) -> response_handlers.ReplState,
        response_handlers.ReplState
    ),  
    ReplError
    ) {

    case string.split(line, " ") {

        [cmd, ..rest] -> {

            case cmd {

                "register" -> {

                    case rest {

                        [username, password] -> {

                            let #(pub_key, priv_key) = rsa_keys.generate_rsa_keys()
                            let new_state = response_handlers.ReplState(
                                ..state,
                                priv_key: priv_key.pem,
                                pub_key: pub_key.pem,
                                user_name: username,

                            )
                            Ok(
                                #(
                                request_builders.register_user(username, password, pub_key.pem, state.server_ip),
                                response_handlers.register_user,
                                new_state,
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "login" -> {

                    case rest {

                        [username, password] -> {

                            let #(pub_key, priv_key) = rsa_keys.generate_rsa_keys()
                            let new_state = response_handlers.ReplState(
                                ..state,
                                priv_key: priv_key.pem,
                                pub_key: pub_key.pem,
                                user_name: username
                            )
                            Ok(
                                #(
                                request_builders.login_user(username, password, pub_key.pem, state.server_ip),
                                response_handlers.login_user,
                                new_state,
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "search-user" -> {

                    case rest {

                        [username] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            let new_state = response_handlers.ReplState(
                                ..state,
                                to_update_user_name: username,
                            )
                            Ok(
                                #(
                                request_builders.search_user(username, user_id, state.signature, state.server_ip),
                                response_handlers.search_user,
                                new_state,
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "create-subreddit" -> {

                    case rest {

                        [subreddit_name] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )

                            let new_state = response_handlers.ReplState(
                                ..state,
                                to_update_subreddit_name: subreddit_name,
                            )

                            Ok(
                                #(
                                request_builders.create_subreddit(subreddit_name, user_id, state.signature, state.server_ip),
                                response_handlers.create_subreddit,
                                new_state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "join-subreddit" -> {

                    case rest {

                        [subreddit_name] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use subreddit_id <- result.try(
                                result.map_error(
                                    dict.get(state.subreddit_rev_index, subreddit_name),
                                    fn(_) {SubredditUnknownError}
                                )
                            )
                            Ok(
                                #(
                                request_builders.join_subreddit(subreddit_name, subreddit_id, user_id, state.signature, state.server_ip),
                                response_handlers.join_subreddit,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "search-subreddit" -> {

                    case rest {

                        [subreddit_name] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )

                            let new_state = response_handlers.ReplState(
                                ..state,
                                to_update_subreddit_name: subreddit_name,
                            )
                            Ok(
                                #(
                                request_builders.search_subreddit(subreddit_name, user_id, state.signature, state.server_ip),
                                response_handlers.search_subreddit,
                                new_state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "leave-subreddit" -> {

                    case rest {

                        [subreddit_name] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use subreddit_id <- result.try(
                                result.map_error(
                                    dict.get(state.subreddit_rev_index, subreddit_name),
                                    fn(_) {SubredditUnknownError}
                                )
                            )

                            Ok(
                                #(
                                request_builders.leave_subreddit(subreddit_name, subreddit_id, user_id, state.signature, state.server_ip),
                                response_handlers.leave_subreddit,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "create-post" -> {

                    case rest {

                        ["--subreddit-name", subreddit_name, ..post] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use subreddit_id <- result.try(
                                result.map_error(
                                    dict.get(state.subreddit_rev_index, subreddit_name),
                                    fn(_) {SubredditUnknownError}
                                )
                            )
                            use #(title, body) <- result.try(
                                fn(){

                                    case post {

                                        ["--title", title, "--body", body] -> Ok(#(title, body))

                                        _ -> Error(CommandError)
                                    }
                                }()
                            )
                            use post <- result.try(
                                fn() {

                                    let post = gen_types.Post(
                                        id: "",
                                        title: title,
                                        body: body,
                                        owner_id: user_id,
                                        subreddit_id: subreddit_id,
                                        upvotes: 0,
                                        downvotes: 0,
                                        signature: "",
                                        owner_name: state.user_name
                                    )
                                    case utls.get_post_sig(post, state.priv_key) {

                                        Ok(sig) -> {

                                            Ok(gen_types.Post(
                                                ..post,
                                                signature: sig|>bit_array.base16_encode, 
                                            ))
                                        }

                                        Error(err) -> {

                                            Error(SignPostFailedError(err))
                                        }
                                    }
                                }()
                            )

                            Ok(
                                #(
                                request_builders.create_post(post, state.signature, state.server_ip),
                                response_handlers.create_post,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "repost" -> {

                    case rest {

                        [post_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use post <- result.try(
                                result.map_error(
                                    dict.get(state.posts_data, post_id),
                                    fn(_) {PostDoesntExistError}
                                )
                            )
                            use post_sig <- result.try(
                                result.map_error(
                                    utls.get_post_sig(post, state.priv_key),
                                    fn(err) {SignPostFailedError(err)}
                                )
                            )
                            Ok(
                                #(
                                request_builders.create_repost(
                                    post_id, 
                                    user_id,
                                    post_sig|>bit_array.base16_encode,
                                    state.signature,
                                    state.server_ip
                                ),
                                response_handlers.create_repost,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "delete-post" -> {

                    case rest {

                        [post_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            Ok(
                                #(
                                request_builders.delete_post(post_id, user_id, state.signature, state.server_ip),
                                response_handlers.delete_post,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "get-post" -> {

                    case rest {

                        [post_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )

                            Ok(
                                #(
                                request_builders.get_post(post_id, user_id, state.signature, state.server_ip),
                                response_handlers.get_post,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }
                
                "create-comment" -> {

                    case rest {

                        ["--parent-id", parent_id, "--body", body] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use parent_id <- result.try(
                                result.map_error(
                                    fn() {
                                        case list.find(state.posts, fn(a){a==parent_id}) {

                                            Ok(parent_id) -> Ok(parent_id)

                                            Error(_) -> {

                                                case list.find(state.comments, fn(a){a==parent_id}) {

                                                    Ok(id) -> Ok(id)

                                                    Error(_) -> Error(Nil)
                                                }
                                            }
                                        }
                                    }(),
                                    fn(_) {InvalidParentError}
                                )
                            )

                            Ok(
                                #(
                                request_builders.create_comment(parent_id, user_id, body, state.signature, state.server_ip),
                                response_handlers.create_comment,
                                state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "downvote" -> {

                    case rest {

                        [parent_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use parent_id <- result.try(
                                result.map_error(
                                    fn() {
                                        case list.find(state.posts, fn(a){a==parent_id}) {

                                            Ok(parent_id) -> Ok(parent_id)

                                            Error(_) -> {

                                                case list.find(state.comments, fn(a){a==parent_id}) {

                                                    Ok(id) -> Ok(id)

                                                    Error(_) -> Error(Nil)
                                                }
                                            }
                                        }
                                    }(),
                                    fn(_) {InvalidParentError}
                                )
                            )

                            Ok(
                                #(
                                request_builders.create_vote(parent_id, user_id, "down", state.signature, state.server_ip),
                                response_handlers.create_vote,
                                state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "upvote" -> {

                    case rest {

                        [parent_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use parent_id <- result.try(
                                result.map_error(
                                    fn() {
                                        case list.find(state.posts, fn(a){a==parent_id}) {

                                            Ok(parent_id) -> Ok(parent_id)

                                            Error(_) -> {

                                                case list.find(state.comments, fn(a){a==parent_id}) {

                                                    Ok(id) -> Ok(id)

                                                    Error(_) -> Error(Nil)
                                                }
                                            }
                                        }
                                    }(),
                                    fn(_) {InvalidParentError}
                                )
                            )

                            Ok(
                                #(
                                request_builders.create_vote(parent_id, user_id, "up", state.signature, state.server_ip),
                                response_handlers.create_vote,
                                state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "unvote" -> {

                    case rest {

                        [parent_id] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use parent_id <- result.try(
                                result.map_error(
                                    fn() {
                                        case list.find(state.posts, fn(a){a==parent_id}) {

                                            Ok(parent_id) -> Ok(parent_id)

                                            Error(_) -> {

                                                case list.find(state.comments, fn(a){a==parent_id}) {

                                                    Ok(id) -> Ok(id)

                                                    Error(_) -> Error(Nil)
                                                }
                                            }
                                        }
                                    }(),
                                    fn(_) {InvalidParentError}
                                )
                            )

                            Ok(
                                #(
                                request_builders.create_vote(parent_id, user_id, "remove", state.signature, state.server_ip),
                                response_handlers.create_vote,
                                state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "get-feed" -> {

                    case rest {

                        [] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            Ok(
                                #(
                                request_builders.get_feed(user_id, state.signature, state.server_ip),
                                response_handlers.get_feed,
                                state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "get-subredditfeed" -> {

                    case rest {

                        [subreddit_name] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use subreddit_id <- result.try(
                                result.map_error(
                                    dict.get(state.subreddit_rev_index, subreddit_name),
                                    fn(_) {SubredditUnknownError}
                                )
                            )
                            Ok(
                                #(
                                request_builders.get_subredditfeed(subreddit_id, user_id, state.signature, state.server_ip),
                                response_handlers.get_subredditfeed,
                                state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "send-dm" -> {

                    case rest {

                        ["--to", user_name, "--message", msg] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use to_send_id <- result.try(
                                result.map_error(
                                    dict.get(state.user_rev_index, user_name),
                                    fn(_) {UserUnknownError}
                                )
                            )
                            use _ <- result.try(
                                    fn() {
                                        case dict.get(state.user_dm_map, to_send_id) {

                                            Ok(dm_id) -> Error(DmExistsError(dm_id))

                                            Error(_) -> Ok(Nil) 
                                        }
                                    }()
                                )
                            let new_state = response_handlers.ReplState(
                                ..state,
                                to_update_user_dm: to_send_id,
                            )
                            Ok(
                                #(
                                request_builders.start_directmessage(to_send_id, user_id, msg, state.signature, state.server_ip),
                                response_handlers.start_directmessage,
                                new_state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "reply-dm" -> {

                    case rest {

                        ["--to", user_name, "--message", msg] -> {

                            use user_id <- result.try(
                                fn() {
                                    case state.user_id == "" {

                                        True -> Error(UnregisteredError)

                                        False -> Ok(state.user_id)
                                    }
                                }()
                            )
                            use to_send_id <- result.try(
                                result.map_error(
                                    dict.get(state.user_rev_index, user_name),
                                    fn(_) {UserUnknownError}
                                )
                            )
                            let new_state = response_handlers.ReplState(
                                ..state,
                                to_update_user_dm: to_send_id,
                            )
                            Ok(
                                #(
                                request_builders.reply_directmessage(to_send_id, user_id, msg, state.signature, state.server_ip),
                                response_handlers.reply_directmessage,
                                new_state
                                )
                            )
                        }
                        _ -> Error(CommandError)
                    }
                }

                "get-dms" -> {

                    use user_id <- result.try(
                        fn() {
                            case state.user_id == "" {

                                True -> Error(UnregisteredError)

                                False -> Ok(state.user_id)
                            }
                        }()
                    )
                    Ok(
                        #(
                        request_builders.get_directmessages(user_id, state.signature, state.server_ip),
                        response_handlers.get_directmessages,
                        state
                        )
                    )
                }

                _ -> Error(CommandError)
            }
        }

        _ -> Error(CommandError) 
    }
}


pub fn main() {

    let domain_name = case argv.load().arguments {

        ["--server-ip", ip] -> ip

        _ -> "localhost"
    }

    let init_state = response_handlers.ReplState(
                        server_ip: domain_name,
                        user_id: "",
                        user_name: "",
                        subreddits: [],
                        to_update_subreddit_name: "",
                        subreddit_rev_index: dict.new(),
                        posts: [],
                        comments: [],
                        users: [],
                        to_update_user_name: "",
                        user_rev_index: dict.new(),
                        user_dm_map: dict.new(),
                        to_update_user_dm: "",
                        priv_key: "",
                        pub_key: "",
                        pub_key_map: dict.new(),
                        posts_data: dict.new(),
                        signature: "",
                    )
    start_repl(init_state)
}

