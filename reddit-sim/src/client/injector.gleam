import gleam/io
import gleam/list
import gleam/dict.{type Dict}
import gleam/int
import gleam/string

import gleam/erlang/process

import simplifile

import generated/generated_types as gen_types 

fn message_injector(
    client_subs:  Dict(Int, process.Subject(gen_types.UserMessage)),
    message_client_map: Dict(gen_types.UserMessage, List(Int)),
    ) -> Nil {

    //io.println("sending injection messages")

    dict.each(message_client_map, fn(curr_msg, user_id_list) {

                                list.each(user_id_list, fn(id) {

                                                            //io.println("checking id for injection " <> int.to_string(id))
                                                            case dict.get(client_subs, id) {

                                                                Ok(sub) -> {

                                                                    //io.println("sending message to " <> int.to_string(id))
                                                                    process.send(sub, curr_msg)
                                                                }

                                                                Error(_) -> {

                                                                    //io.println("sending message to " <> int.to_string(id))
                                                                    Nil
                                                                }
                                                            }
                                                        }
                                )
                            }
    )
}

fn parse_config_file(
    message_map: Dict(String, gen_types.UserMessage)
    ) -> Dict(gen_types.UserMessage, List(Int)) {

    let msg = case simplifile.read("./config/messages.shr") {

        Ok(str) -> {

            let ret = dict.new()

            let msg_dict = string.split(string.trim(str), "\n")
            |> list.fold(
                ret, 
                fn(msg_dict, line) {

                    //io.println("curr line " <> line)
                    let assert [k, v] = string.split(string.trim(line), ":")

                    let tmp = []
                    let v = string.split(v, ",")
                    |> list.fold(
                        tmp,
                        fn(tmp_list, num) {

                            case int.parse(string.trim(num)) {

                              Ok(number) -> {
                    //io.println("curr num_list val " <> int.to_string(number))
                                  [number, ..tmp_list]
                              }

                              Error(_) -> {

                                  panic as "Config file had invalid type as number"
                              }
                           }
                        }
                       )
                    let k = case dict.get(message_map, k) {

                        Ok(msg) -> {


                            //echo msg
                            msg 
                        }

                        Error(_) -> {

                            io.println("Invalid message " <> k)
                            panic as "Invalid message type while parsing config file" 
                        }
                    }

                dict.insert(msg_dict, k, v)
                }
               )

            msg_dict
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


pub fn start_injection(
    client_subs:  Dict(Int, process.Subject(gen_types.UserMessage)),
    ) -> process.Pid {

    process.spawn(fn () {
                    parse_config_file(gen_types.message_translator())
                    |> message_injector(client_subs, _)
                  }
    )
} 

