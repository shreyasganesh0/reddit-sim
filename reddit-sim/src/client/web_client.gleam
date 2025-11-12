import in
import gleam/io
import gleam/string
import gleam/result
import gleam/bit_array
import gleam/dict

import gleam/http/request
import gleam/http/response
import gleam/httpc

import client/response_handlers
import client/request_builders

type ReplError {

    CommandError

    ReadError(in.Error)

    RequestError(httpc.HttpError)

    UnregisteredError

    SubredditUnknownError
}


fn start_repl(state: response_handlers.ReplState) {

    io.println("[CLIENT]: enter command...")
    let res = {

        use line <- result.try(result.map_error(in.read_line(), fn(e) {ReadError(e)}))
        let line = string.trim(line)
        case line {

            "logout"-> {

                Ok(#(response.new(200)|>response.map(bit_array.from_string), response_handlers.logout, state))
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

                            Ok(
                                #(
                                request_builders.register_user(username, password),
                                response_handlers.register_user,
                                state,
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }

                "login" -> {

                    case rest {

                        [username, password] -> {

                            Ok(
                                #(
                                request_builders.login_user(username, password),
                                response_handlers.login_user,
                                state,
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
                                request_builders.create_subreddit(subreddit_name, user_id),
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
                            echo subreddit_id

                            Ok(
                                #(
                                request_builders.join_subreddit(subreddit_name, subreddit_id, user_id),
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
                                request_builders.search_subreddit(subreddit_name, user_id),
                                response_handlers.search_subreddit,
                                new_state
                                )
                            )
                        }

                        _ -> Error(CommandError)
                    }
                }
                
                _ -> Error(CommandError)
            }
        }

        _ -> Error(CommandError) 
    }
}


pub fn main() {

    let init_state = response_handlers.ReplState(
                        user_id: "",
                        subreddits: [],
                        to_update_subreddit_name: "",
                        subreddit_rev_index: dict.new()
                    )
    start_repl(init_state)
}


