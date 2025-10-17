import gleam/io
import gleam/int
import argv

import client/users
import server/engine

type ArgsError {

    InvalidArgs

    WrongArgCount(required: Int)
}

type BuildType {

    Server

    Client
}

pub fn main() -> Nil {

    let res = case argv.load().arguments {

        [build_type] -> {

            case build_type {

                "server" -> {

                    Ok(#(Server, 0))
                }

                "client" -> {

                    io.println("Invalid use of client type, Usage: gleam run client numUsers") 
                    Error(InvalidArgs)
                }

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|client] [numUsers]")
                    Error(InvalidArgs)
                }
            }
        }

        [build_type, numusers] -> {

            case build_type {

                "client" -> {

                    case int.parse(numusers) {

                        Ok(users) -> {

                            case users >= 1 {

                                True -> Ok(#(Client, users))

                                False -> Error(InvalidArgs)  
                            }
                        }

                        Error(_) -> { 

                            Error(InvalidArgs)
                        }
                    }
                }

                _ -> {

                    io.println("Invalid build type, Usage: gleam run [server|client] [numUsers]")
                    Error(InvalidArgs)
                }
            }
        }

        _ -> {

            Error(WrongArgCount(1))
        }
    }

    case res {

        Ok(#(build_type, num_users)) -> {

            case build_type {

                Server -> {

                    engine.create()
                }

                Client -> {

                    users.create(num_users)
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
