import gleam/set.{type Set}
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import gleam/io
import gleam/int

import simplifile

type Typ {

    Typ(
        type_name: String,
        type_fields: Dict(String, String) 
    )
}

type Msg {
    
    Msg(
        type_name: String,
        type_fields: Dict(String, String) 
    )
}

type ParsedFile {

    ParsedFile(
        types_set: Set(String),
        types_list: List(Typ),
        msgs_list: List(Msg),
    )
}

pub fn main() -> Nil {

    read_conf()
}

fn create_selectors_imports() -> String {

    "import gleam/dynamic/decode\n"
    <>"import gleam/dynamic\n"
    <>"import gleam/result\n"
    <>"import generated/generated_types\n\n"
    <>"import generated/generated_decoders\n\n"
}

fn read_conf() -> Nil {

    let file_data = ParsedFile(
        types_set: set.from_list(["string", "int", "float", "pid"]),
        types_list: [],
        msgs_list: [],
    )

    let file_data = case simplifile.read("config/codegen.shr") {

        Ok(file_str) ->  {

            echo file_str

            string.trim(file_str)
            |> string.split("$$$\n") 
            |> list.filter_map(fn(s) { 
              let new_s = string.trim(s)
              case  new_s != "" {

                  True -> Ok(new_s)
                  False -> Error(new_s)
              }
              })
            |> list.fold(file_data, fn(file_data, section) {

                            parse_section(section, file_data)
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

            file_data
        }
    }

    case ""
    |> generate_types(file_data.types_list)
    |> string.append("\n\n")
    |> generate_msgs(file_data.msgs_list)
    |> simplifile.write("src/generated/generated_types.gleam", _) {

        Ok(_) -> io.println("generated_files at src/generated")

        Error(err) -> {

            io.println(simplifile.describe_error(err))
            io.println("\n\n--------------\n\n")

        }
    }

    case create_selectors_imports() 
    |> generate_selectors(file_data.msgs_list)
    |> simplifile.write("src/generated/generated_selectors.gleam", _) {

        Ok(_) -> io.println("generated_files at src/generated")

        Error(err) -> {

            io.println(simplifile.describe_error(err))
            io.println("\n\n--------------\n\n")

        }
    }

    case decoder_str()
    |> simplifile.write("src/generated/generated_decoders.gleam", _) {

        Ok(_) -> io.println("generated_files at src/generated")

        Error(err) -> {

            io.println(simplifile.describe_error(err))
            io.println("\n\n--------------\n\n")

        }
    }
    Nil
}

fn decoder_str() -> String {

"import gleam/io

import gleam/erlang/process
import gleam/dynamic
import gleam/dynamic/decode

import utls
import generated/generated_types

@external(erlang, \"erlang\", \"is_pid\")
fn is_pid(pid: dynamic.Dynamic) -> Bool 

pub fn pid_decoder(_data: dynamic.Dynamic) -> decode.Decoder(process.Pid) { 

    let pid_decode = fn(data) {
        let default_pid = process.spawn_unlinked(fn(){Nil})
        process.kill(default_pid)

         {
            case is_pid(data) {

                True -> {

                    let pid: process.Pid = utls.unsafe_coerce(data)
                    Ok(pid)
                }

                False -> { 
                    
                    io.println(\"fail pid check\")
                    Error(default_pid)
                }
            }
        }
    }
    decode.new_primitive_decoder(\"Pid\", pid_decode)
}


pub fn post_serializer(post: generated_types.Post) -> dynamic.Dynamic {

    dynamic.properties([
        #(dynamic.string(\"title\"), dynamic.string(post.title)),
        #(dynamic.string(\"body\"), dynamic.string(post.body)),
        ])

}

pub fn post_decoder() -> decode.Decoder(generated_types.Post) {

    use title <- decode.field(\"title\", decode.string)
    use body <- decode.field(\"body\", decode.string)
    decode.success(generated_types.Post(title: title, body: body))
}
"
}

fn caseify(field: String) -> String {

    let field = string.split(field, "_")
    |> list.map(string.capitalise)
    |> string.join("")

    case field {

        "Pid" -> {

            "process."<>field
        }

        _ -> field
    }
}

fn generate_msgs(prefix: String, msgs: List(Msg)) {

    "pub type EngineMessage {\n\n"
    |> generate_engine_msgs(msgs)
    |> string.append("\n}\n\npub type UserMessage {\n\n")
    |> generate_user_msgs(msgs)
    |> string.append("\n}\n\n")
    |> string.append(prefix, _)

    //generate_injectors(msgs)
}

fn generate_selectors(prefix: String, msgs: List(Msg)) -> String {

    let data = []
    list.fold(
        msgs,
        data,
        fn(data, msg) {

            [
            string.join([create_engine_selector(msg), ..create_user_selectors(msg)], "\n\n"),
            ..data
            ]
        }
    )
    |> string.join("\n\n//------------------------------------------------------------------\n\n")
    |> string.append(prefix, _)
}

fn get_decoder_string(typ: String) -> String {

    case typ {

        "pid" -> {

            "generated_decoders.pid_decoder()"
        }

        "post" -> {

            "generated_decoders.post_decoder()"
        }

        _ -> {

            "decode."<>typ
        }
    }
}

fn create_user_selectors(msg: Msg) -> List(String) {

    let Msg(type_name, _type_fields) = msg

    let fail_def = "pub fn "<>type_name<>"_failed_selector(\n\tdata: dynamic.Dynamic\n\t) -> generated_types.UserMessage {\n\n\tlet res = {\n\n"
    
    let success_fn_def = "pub fn "<>type_name<>"_success_selector(\n\tdata: dynamic.Dynamic\n\t) -> generated_types.UserMessage {\n\n\tcase decode.run(data, decode.at([1], decode.string)) {\n\n\t\tOk(name) -> {\n\n\t\t\tgenerated_types."<>caseify(type_name)<>"Success(name)\n\t\t}\n\n\t\tError(_) -> {\n\n\t\t\tpanic as \"illegal value passed to "<>caseify(type_name)<>"Success\"\n\t\t\t}\n\t\t}\n}"


    let fail_fields_dict = dict.from_list([#("name", "string"), #("fail_reason", "string")]) 
    let fields = []
    let types_list = []
    let num = 1
    let #(_, use_fields, types_list) = dict.fold(
        fail_fields_dict,
        #(num, fields, types_list),
        fn(tupper, k, v) {

            let #(a, fields, types_list) = tupper 

            #(
            a + 1,
            [
            "\t\tuse "<>k<>" <- result.try(decode.run(data, decode.at(["<>int.to_string(a)<>"], "
            <>get_decoder_string(v)<>")))",
            ..fields
            ],
            [k, ..types_list],
            )
        }
    )
    let failed_use_field = string.join(use_fields, "\n")
    
    let types_tup = "("<>string.join(types_list, ", ")<>")"
    let failed_use_ret = "\n\t\tOk(#"<>types_tup<>")\n\t}\n\n\tcase res {\n\n\t\tOk(#"
        <>types_tup<>") -> {\n\n\t\t\tgenerated_types."<>caseify(type_name)<>"Failed"<>types_tup<>
        "\n\t\t}\n\n\t\tError(_) -> {\n\n\t\t\tpanic as \"illegal value passed to "<>caseify(type_name)<>"Failed message\"\n\t\t}\n\t}\n}"


    [success_fn_def, fail_def<>failed_use_field<>failed_use_ret]

}

fn create_engine_selector(msg: Msg) -> String {

    let Msg(type_name, type_fields) = msg

    let fn_def = "pub fn "<>type_name<>"_selector(\n\tdata: dynamic.Dynamic\n\t) -> generated_types.EngineMessage {\n\n\tlet res = {\n\n"
    let fields = []
    let types_list = []
    let num = 1
    let #(_, use_fields, types_list) = dict.fold(
        type_fields,
        #(num, fields, types_list),
        fn(tupper, k, v) {

            let #(a, fields, types_list) = tupper 

            #(
            a + 1,
            [
            "\t\tuse "<>k<>" <- result.try(decode.run(data, decode.at(["<>int.to_string(a)<>"], "
            <>get_decoder_string(v)<>")))",
            ..fields
            ],
            [k, ..types_list],
            )
        }
    )
    let use_fields = string.join(use_fields, "\n")

    let types_tup = "("<>string.join(types_list, ", ")<>")"
    let use_ret = "\n\t\tOk(#"<>types_tup<>")\n\t}\n\n\tcase res {\n\n\t\tOk(#"
        <>types_tup<>") -> {\n\n\t\t\tgenerated_types."<>caseify(type_name)<>types_tup<>
        "\n\t\t}\n\n\t\tError(_) -> {\n\n\t\t\tpanic as \"Failed to parse message register user\"\n\t\t}\n\t}\n}"
    
    fn_def<>use_fields<>use_ret
}

fn generate_engine_msgs(prefix: String, msgs: List(Msg)) -> String {

    let data = []
    list.fold(
        msgs,
        data,
        fn(data, msg) {

            let Msg(type_name, type_fields) = msg

            let type_name = caseify(type_name)
            let fields = []
            let fields = dict.fold(
                type_fields,
                fields,
                fn(fields, k, v) {

                    let v = caseify(v)
                    ["\t\t"<>k<>": "<>v, ..fields]
                }
            )
            |> string.join(",\n")
            
            ["\t"<>type_name<>"(\n"<>fields<>"\n\t)", ..data]
        }
    )
    |> string.join("\n\n")
    |> string.append(prefix, _)

}

fn generate_user_msgs(prefix: String, msgs: List(Msg)) {

    let data = []
    list.fold(
        msgs,
        data,
        fn(data, msg) {

            let Msg(type_name, _type_fields) = msg 

            let type_name = caseify(type_name)
            let type_name_failed = type_name <> "Failed"
            let type_name_success = type_name <> "Success"
            let type_name_inject = "Inject" <> type_name

            let success_fields = "\t\tsubreddit_name: String"
            let fail_fields = success_fields <> ",\n\t\tfail_reason: String"

            [
            "\t"<>type_name_success<>"(\n"<>success_fields<>"\n\t)",
            "\t"<>type_name_failed<>"(\n"<>fail_fields<>"\n\t)", 
            "\t"<>type_name_inject, ..data
            ]
        }
    )
    |> string.join("\n\n")
    |> string.append(prefix, _)
}

fn generate_types(_strs: String, types_list: List(Typ)) {

    let data = []
    list.fold(
        types_list, 
        data,
        fn(data, typ) {

            let Typ(type_name, type_fields) = typ

            let type_name = caseify(type_name)
            let fields = []
            let fields = dict.fold(
                type_fields,
                fields,
                fn(fields, k, v) {

                    let v = caseify(v)
                    ["\t\t"<>k<>": "<>v, ..fields]
                }
            )
            |> string.join(",\n")
            
            ["pub type "<>type_name<>" {\n\n\t"<>type_name<>"(\n"<>fields<>"\n\t)\n\n}", ..data]
        }
    )
    |> string.join("\n\n")
}

fn parse_section(
    section: String,
    file_data: ParsedFile,
    ) -> ParsedFile {

    let section_list = string.trim(section)
    |> string.split("\n")
    |> list.filter_map(fn(s) { 
      let new_s = string.trim(s)
      case  new_s != "" {

          True -> Ok(new_s)
          False -> Error(new_s)
      }
      })

    case section_list {

        [section_t, ..data] -> {

            case section_t {

                "typ" -> {

                    list.fold(
                            data,
                            file_data,
                            fn(file_data, line) {

                                let #(name, fields) = build_section(line, build_typ_kv, file_data.types_set)
                                let types_list = [Typ(name, fields), ..file_data.types_list] 
                                let types_set = set.insert(file_data.types_set, name)
                                ParsedFile(
                                    ..file_data,
                                    types_list: types_list,
                                    types_set: types_set,
                                )
                            }
                    )
                }

                "msg" -> {

                echo file_data
                    list.fold(
                            data,
                            file_data,
                            fn(file_data, line) {
                                
                                let #(name, fields) = build_section(line, build_msg_kv, file_data.types_set)
                                let msg = Msg(name, fields)
                                let msg_list = [
                                                msg,
                                                ..file_data.msgs_list
                                               ]
                                ParsedFile(
                                    ..file_data,
                                    msgs_list: msg_list
                                )
                            }
                    )
                }

                _ -> panic as "invalid section name" 
            }
        }

        _ -> panic as "section did not conform to structure section_type/\ndata"
    }
}

fn build_msg_kv(str_kv: List(String), types_set: Set(String)) -> Dict(String, String) {

    let kv_dict: Dict(String, String) = dict.new()
    list.fold(str_kv, kv_dict, fn(kv_dict, kv) {

                          let assert [field_name, field_type] = string.split(kv, ":")
                          |> list.filter_map(fn(s) { 
                              let new_s = string.trim(s)
                              case  new_s != "" {

                                  True -> Ok(new_s)
                                  False -> Error(new_s)
                              }
                              })
                        
                          echo types_set

                          echo field_type
                          let _ = case set.contains(types_set, field_type) {

                              True -> "" 

                              False -> panic as "Type was not defined before msg. Please add a defintion of all types use in fields of messages"
                          }

                          dict.insert(kv_dict, field_name, field_type)

                      }
    ) 
}

fn build_typ_kv(str_kv: List(String), _: Set(String)) -> Dict(String, String) {

    let kv_dict: Dict(String, String) = dict.new()
    list.fold(str_kv, kv_dict, fn(kv_dict, kv) {

                          let assert [field_name, field_type] = string.split(kv, ":")
                          |> list.filter_map(fn(s) { 
                              let new_s = string.trim(s)
                              case  new_s != "" {

                                  True -> Ok(new_s)
                                  False -> Error(new_s)
                              }
                              })


                          dict.insert(kv_dict, field_name, field_type)

                      }
    ) 
}

fn build_section(
    line: String,
    kv_builder: fn(List(String), Set(String)) -> Dict(String, String),
    types_set: Set(String)) -> #(String, Dict(String, String)) {

    let assert [type_name, str_type_fields] = string.split(line, "|||")
    |> list.filter_map(fn(s) { 
      let new_s = string.trim(s)
      case  new_s != "" {

          True -> Ok(new_s)
          False -> Error(new_s)
      }
      })

    let kv_dict = string.split(str_type_fields, ", ")
    |> list.filter_map(fn(s) { 
      let new_s = string.trim(s)
      case  new_s != "" {

          True -> Ok(new_s)
          False -> Error(new_s)
      }
      })
    |> kv_builder(types_set)

    #(type_name, kv_dict)
}
