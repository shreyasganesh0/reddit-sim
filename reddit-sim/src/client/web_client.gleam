import in
import gleam/io
import gleam/string
import gleam/result

import gleam/http/request
import gleam/http/response
import gleam/httpc

import client/response_handlers
import client/request_builders

type ReplError {

    CommandError

    ReadError(in.Error)

    RequestError(httpc.HttpError)
}


fn start_repl(state: response_handlers.ReplState) {

    io.println("[CLIENT]: enter command...")
    let res = {

        use line <- result.try(result.map_error(in.read_line(), fn(e) {ReadError(e)}))
        use #(req, resp_handler) <- result.try(parse_line(line))
        use resp <- result.try(
            result.map_error(
                httpc.configure()
                |> httpc.verify_tls(False)
                |> httpc.dispatch_bits(req),
                fn(e) {RequestError(e)}
            )
        )
        Ok(#(resp, resp_handler))
    }

    let new_state = case res {

        Ok(#(resp, resp_handler)) -> {

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
            }

            state
        }
    }

    start_repl(new_state)
}

fn parse_line(line: String) -> Result(
    #(
        request.Request(BitArray),
        fn(response.Response(BitArray), response_handlers.ReplState) -> response_handlers.ReplState
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
                                response_handlers.register_user
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
                    )
    start_repl(init_state)
}


