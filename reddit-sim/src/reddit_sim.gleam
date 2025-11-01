import gleam/io
import gleam/int
import gleam/result
import argv

import client/users
import server/engine
import metrics/metrics

type ArgsError {

    InvalidArgs

    WrongArgCount(required: Int)
}

type BuildType {

    Server

    Client

    Metrics
}

pub fn main() -> Nil {

    let res = case argv.load().arguments {

        [build_type, num_users] -> {

            use numusers <- result.try(fn() {
                case int.parse(num_users) {

                    Ok(users) -> {

                        case users >= 1 {

                            True -> Ok(users)

                            False -> Error(InvalidArgs)  
                        }
                    }

                    Error(_) -> { 

                        Error(InvalidArgs)
                    }
                }
            }())

            
            case build_type {

                "server" -> {

                    Ok(#(Server, "", numusers, 0))
                }

                "metrics" -> {

                    Ok(#(Metrics, "", numusers, 0))
                }
                "client" -> {

                    io.println("Invalid use of client type, Usage: gleam run client numUsers") 
                    Error(InvalidArgs)
                }

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|metrics|client] numUsers [runTimeSeconds]")
                    Error(InvalidArgs)
                }
            }
        }

        [build_type, client_mode, num_users, run_time] -> {

            case build_type {

                "client" -> {

                    use clientmode <- result.try(fn() {
                        case client_mode {

                            "simulator" -> {

                                Ok(client_mode)
                            }

                            "web_server" -> {

                                Ok(client_mode)
                            }

                            _ -> Error(InvalidArgs)
                        }
                    }())

                    use numusers <- result.try(fn() {
                        case int.parse(num_users) {

                            Ok(users) -> {

                                case users >= 1 {

                                    True -> Ok(users)

                                    False -> Error(InvalidArgs)  
                                }
                            }

                            Error(_) -> { 

                                Error(InvalidArgs)
                            }
                        }
                    }())
                    use runtime <- result.try(result.map_error(int.parse(run_time), fn(_) {InvalidArgs}))

                    Ok(#(Client, clientmode, numusers, runtime))
                }

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|metrics|client] numUsers [runTimeSeconds]")
                    Error(InvalidArgs)
                }
            }
        }

        _ -> {

            Error(WrongArgCount(3))
        }
    }

    case res {

        Ok(#(build_type, client_mode, num_users, run_time)) -> {

            case build_type {

                Server -> {

                    engine.create(num_users)
                }

                Client -> {

                    users.create(client_mode, num_users, run_time)
                }

                Metrics -> {
                    
                    metrics.create(num_users)
                }
            }

        }

        Error(err) -> {

            case err {

                InvalidArgs -> {

                    io.println("Received invalid args\nUsage: gleam run numUsers")
                }

                WrongArgCount(n) -> {

                    io.println("Received wrong number of args: " <> int.to_string(n) <>"\nUsage: gleam run numUsers")

                }
            }
        }
    }
}
