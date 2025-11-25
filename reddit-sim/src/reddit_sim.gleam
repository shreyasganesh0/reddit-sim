import gleam/io
import gleam/int
import gleam/list
import gleam/result
import argv

import client/users
import server/engine
import metrics/metrics
import server/web_server

type ArgsError {

    InvalidArgs

    WrongArgCount(required: Int)
}

type BuildType {

    Server

    Client

    Metrics

    ApiGateway
}

pub fn main() -> Nil {

    let res = case argv.load().arguments {

        [build_type, self_ip, engine_ip] -> {

            case build_type {

                "api_gateway" -> Ok(#(ApiGateway, engine_ip, "", self_ip, 0, 0))
                
                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|metrics|client|api_gateway] ip numUsers [runTimeSeconds]")
                    Error(InvalidArgs)
                }
            }
        }

        [build_type, engine_ip_or_metrics_ip, num_users, self_ip] -> {

            use numusers <- result.try(
                fn() {
                case int.parse(num_users) {

                    Ok(users) -> {

                        case users >= 1 {

                            True -> Ok(users)

                            False -> Error(InvalidArgs)  
                        }
                    }

                    Error(_) -> Error(InvalidArgs)
                }
                }()
            )
            case build_type {

                "server" -> Ok(#(Server, "", engine_ip_or_metrics_ip, self_ip, numusers, 0))

                "metrics" -> Ok(#(Metrics, engine_ip_or_metrics_ip, "", self_ip, numusers, 0))

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|metrics|client|api_gateway] ip numUsers [runTimeSeconds]")
                 Error(InvalidArgs)
                }
            }
        }


        [build_type, metrics_ip, engine_ip, num_users, run_time, self_ip] -> {

            case build_type {

                "client" -> {

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

                    Ok(#(Client, metrics_ip, engine_ip, self_ip, numusers, runtime))

                }

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|metrics|client|api_gateway] ip numUsers [runTimeSeconds]")
                    Error(InvalidArgs)
                }
            }
        }

        [..args] -> {

            echo args
            Error(WrongArgCount(list.length(args)))
        }
    }

    case res {

        Ok(#(build_type, ip1, ip2, ip3, num_users, run_time)) -> {

            case build_type {

                Server -> {

                    engine.create(ip2, num_users, ip3)
                }

                Client -> {

                    users.create(ip1, ip2, num_users, run_time, ip3)
                }

                Metrics -> {
                    
                    metrics.create(ip1, num_users, ip3)
                }

                ApiGateway -> {

                    web_server.create(ip1, ip3)
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
