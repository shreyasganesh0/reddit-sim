import gleam/set.{type Set}
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import gleam/io

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

fn read_conf() -> Nil {

    let file_data = ParsedFile(
        types_set: set.from_list(["string", "int", "float", "pid"]),
        types_list: [],
        msgs_list: [],
    )

    let file_data = case simplifile.read("config/codegen.shr") {

        Ok(file_str) ->  {

            echo file_str

            let file_list = string.trim(file_str)
            |> string.split("$$$\n") 
            |> list.filter(fn(s) { string.trim(s) != "" })
            list.fold(file_list, file_data, fn(file_data, section) {

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

    echo file_data

    Nil
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
