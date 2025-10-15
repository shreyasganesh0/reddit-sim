import gleam/io
import gleam/int
import gleam/result
import argv

import users

type ArgsError {

    InvalidArgs

    WrongArgCount(required: Int)
}

pub fn main() -> Nil {

    let res = case argv.load().arguments {

        [numusers] -> {

            case int.parse(numusers) {

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
        }

        _ -> {

            Error(WrongArgCount(1))
        }
    }

    case res {

        Ok(num_users) -> {

            users.create(num_users)
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
