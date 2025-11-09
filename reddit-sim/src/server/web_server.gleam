import mist
import gleam/http
import gleam/io
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/request
import gleam/http/response

import gleam/erlang/process
import gleam/erlang/atom
import gleam/erlang/node

import server/api_handlers

import generated/generated_types as gen_types
import generated/generated_decoders as gen_decode
import generated/generated_selectors as gen_select

import utls

@external(erlang, "global", "whereis_name")
fn global_whereisname(name: atom.Atom) -> dynamic.Dynamic 

fn request_handler(
    req: request.Request(mist.Connection), 
    engine_sub: process.Pid,
    self_selector: process.Selector(gen_types.UserMessage)
    ) -> response.Response(mist.ResponseData) {
    

    case req.method, request.path_segments(req) {

        http.Post, ["echo"] -> {
                    
            api_handlers.echo_resp(req)

        }

        http.Post, ["api", "v1", ..rest] -> {

            case rest {

                ["register"] -> {

                    api_handlers.register_user(req, engine_sub, self_selector)
                }

                ["subreddit"] -> {

                    api_handlers.create_subreddit(req, engine_sub, self_selector)
                }
                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Post, ["r", _subreddit_name, "api", ..rest] -> {

            case rest {

                ["subscribe"] -> {

                    api_handlers.join_subreddit(req, engine_sub, self_selector)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Get, ["api", "v1", ..rest] -> {

            case rest {

                ["search_user"] -> {

                    api_handlers.search_user(req, engine_sub, self_selector)
                }
                _ -> api_handlers.error_page_not_found()
            }
        }

        _, _ -> api_handlers.error_page_not_found()
    }
}



pub fn start() {

    //let restserver_node = atom.create("restserver@localhost")
    let engine_node = atom.create("engine@localhost")
    let engine_atom = atom.create("engine")

    case node.connect(engine_node) {
        
        Ok(_node) -> {

            io.println("Connected to engine")
        }

        Error(err) -> {

            case err {

                node.FailedToConnect -> io.println("Node failed to connect")

                node.LocalNodeIsNotAlive -> io.println("Not in distributed mode")
            }
        }

    }

    process.sleep(500)
    let data = global_whereisname(engine_atom)
    let engine_pid = case decode.run(data, gen_decode.pid_decoder()) {

        Ok(engine_pid) -> {

            io.println("Found engine's pid")
            engine_pid
        }

        Error(_) -> {

            io.println("Couldnt find engine's pid")
            panic
        }
    }

    let assert Ok(_) = mist.new(fn(req) {request_handler(req, engine_pid, create_selector())})
    |> mist.bind("localhost")
    |> mist.start
}


fn create_selector() -> process.Selector(gen_types.UserMessage) {

    process.new_selector()
    |> utls.create_selector(gen_select.get_user_selector_list())
    //|> process.select_map(sub, fn(msg) {msg})
}
