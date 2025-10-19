import gleam/io
import gleam/list
import gleam/dict.{type Dict}
import gleam/int
import gleam/string

import gleam/erlang/process

import simplifile

import types

fn message_injector(
    client_subs:  Dict(Int, process.Subject(types.UserMessage)),
    message_client_map: Dict(types.UserMessage, List(Int)),
    ) -> Nil {

    io.println("sending injection messages")

    dict.each(message_client_map, fn(curr_msg, user_id_list) {

                                list.each(user_id_list, fn(id) {

                                                            io.println("checking id for injection " <> int.to_string(id))
                                                            case dict.get(client_subs, id) {

                                                                Ok(sub) -> {

                                                                    io.println("sending message to " 
                                                                        <> int.to_string(id))
                                                                    process.send(sub, curr_msg)
                                                                }

                                                                Error(_) -> {

                                                                    io.println("sending message to " 
                                                                        <> int.to_string(id))
                                                                    Nil
                                                                }
                                                            }
                                                        }
                                )
                            }
    )
}

fn parse_config_file(
    message_map: Dict(String, types.UserMessage)
    ) -> Dict(types.UserMessage, List(Int)) {

    let msg = case simplifile.read("./config/messages.shr") {

        Ok(str) -> {

            let ret = dict.new()

            string.split(string.trim(str), "\n")
            |> list.fold(ret, fn(msg_dict, line) {

                             //io.println("curr line " <> line)
                             let curr_kv = string.split(string.trim(line), ":")
                             let k = types.UserTestMessage
                             let v = []

                             let #(k, v) =list.fold(curr_kv, #(k,v), fn(acc, a) {

                                                    let #(curr_k, _) = acc
                                                    case curr_k == types.UserTestMessage {

                                                        True -> {

                                                            //io.println("curr msg val " <> a)

                                                            case dict.get(message_map, a) {

                                                                Ok(msg) -> {

                                                                    echo msg
                                                                    #(msg, [])
                                                                }

                                                                Error(_) -> {

                                                                    io.println("Invalid message " <> a)
                                                                    panic as "Invalid message type while parsing config file" 
                                                                }
                                                            }

                                                        }

                                                        False -> {


                                                            let tmp = []
                                                            let num_list = string.split(a, ",")
                                                            |> list.fold(tmp, fn(tmp_list, num) {
                                                                                case int.parse(
                                                                                    string.trim(num)) {

                                                                                  Ok(number) -> {
                                                                //io.println("curr num_list val " <> int.to_string(number))
                                                                                      [number,
                                                                                        ..tmp_list]
                                                                                  }

                                                                                  Error(_) -> {

                                                                                      panic as "Config file had invalid type as number"
                                                                                  }
                                                                               }
                                                                              }
                                                               )
                                                            echo num_list
                                                            #(curr_k, num_list)
                                                        }
                                                    }
                                               }
                             )

                             dict.insert(msg_dict, k, v)
                         }
               )
        }

        Error(err) -> {

            io.println(simplifile.describe_error(err))
            io.println("\n\n--------------\n\n")

            case simplifile.get_files(".") {

                Ok(strs) -> {

                    list.each(strs, fn(a) {

                                        io.println(a)
                                    }
                    )
                }

                Error(err) -> {

                    io.println(simplifile.describe_error(err))
                }
            }
            panic as "Couldnt read config file"
        }
    }

    msg
}

fn message_translator() -> Dict(String, types.UserMessage) {

        dict.from_list([
            #("register_user" ,types.InjectRegisterUser),
            #("create_subreddit", types.InjectCreateSubReddit),
            #("join_subreddit", types.InjectJoinSubReddit),
            ])
}
    

pub fn start_injection(
    client_subs:  Dict(Int, process.Subject(types.UserMessage)),
    ) -> process.Pid {

    process.spawn(fn () {
                    parse_config_file(message_translator())
                    |> message_injector(client_subs, _)
                  }
    )
} 

