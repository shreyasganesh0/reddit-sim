import mist
import gleam/http
import gleam/io
import gleam/int
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http/request
import gleam/http/response

import gleam/erlang/process
import gleam/erlang/atom
import gleam/erlang/node

import server/api_handlers
import server/sse_handlers

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
    
    echo req

    case req.method, request.path_segments(req) {

        http.Post, ["echo"] -> {
                    
            api_handlers.echo_resp(req)

        }

        http.Post, ["api", "v1", ..rest] -> {

            case rest {

                ["register"] -> {

                    api_handlers.register_user(req, engine_sub, self_selector)
                }

                ["login"] -> {

                    api_handlers.login_user(req, engine_sub, self_selector)
                }

                ["subreddit"] -> {

                    api_handlers.create_subreddit(req, engine_sub, self_selector)
                }

                ["repost"] -> {

                    api_handlers.create_repost(req, engine_sub, self_selector)
                }

                ["comment"] -> {

                    api_handlers.create_comment(req, engine_sub, self_selector)
                }

                ["vote"] -> {

                    api_handlers.create_vote(req, engine_sub, self_selector)
                }

                ["dm", ..typ] -> {

                    case typ {

                        ["start"] -> api_handlers.start_directmessage(req, engine_sub, self_selector)

                        [_dm_id, "reply"] -> api_handlers.reply_directmessage(req, engine_sub, self_selector)
                        _ -> api_handlers.error_page_not_found()
                    }
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Post, ["r", _subreddit_name, "api", ..rest] -> {

            case rest {

                ["subscribe"] -> {

                    api_handlers.join_subreddit(req, engine_sub, self_selector)
                }

                ["submit"] -> {

                    api_handlers.create_post(req, engine_sub, self_selector)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Delete, ["r", subreddit_id, "api", ..rest] -> {

            case rest {

                ["subscribe"] -> {

                    api_handlers.leave_subreddit(req, engine_sub, self_selector, subreddit_id)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Delete, ["api", "v1", ..rest] -> {

            case rest {

                ["post", post_id] -> {

                    api_handlers.delete_post(req, engine_sub, self_selector, post_id)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Get, ["api", "v1", ..rest] -> {

            case rest {

                ["search_user"] -> {

                    api_handlers.search_user(req, engine_sub, self_selector)
                }

                ["search_subreddit"] -> {

                    api_handlers.search_subreddit(req, engine_sub, self_selector)
                }

                ["post", post_id] -> {

                    api_handlers.get_post(req, engine_sub, self_selector, post_id)
                }

                ["feed"] -> {

                    api_handlers.get_feed(req, engine_sub, self_selector)
                }

                ["dm"] -> {

                    api_handlers.get_directmessages(req, engine_sub, self_selector)
                }

                ["notification"] -> {

                    sse_handlers.register_notifications(req, engine_sub, self_selector)
                }

                _ -> api_handlers.error_page_not_found()
            }
        }

        http.Get, ["r", subreddit_id, "api", ..rest] -> {

            case rest {

                ["posts"] -> {

                    api_handlers.get_subredditfeed(req, engine_sub, self_selector, subreddit_id)
                }

                _ -> api_handlers.error_page_not_found()
            }

        }

        _, _ -> api_handlers.error_page_not_found()
    }
}

fn connect_to_engine(
    retry_count: Int,
    engine_node: atom.Atom,
    engine_atom: atom.Atom,
    ) {

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
    case decode.run(data, gen_decode.pid_decoder()) {

        Ok(engine_pid) -> {

            io.println("Found engine's pid")
            engine_pid
        }

        Error(_) -> {

            io.println("Couldnt find engine's pid")

            case retry_count > 3 {

                True -> {

                    panic as "Maximum retries exceeded.. shutting down. please restart after engine is up"
                } 

                False -> {

                    process.sleep(int.random(300) + {retry_count * 1000})
                    connect_to_engine(retry_count + 1, engine_node, engine_atom)
                }
            }
            process.self()
        }
    }

}

pub fn create(
    self_ip: String,
    engine_ip: String,
    ) -> Nil {

    let main_sub = process.new_subject()
    let engine_node = atom.create("engine@"<>engine_ip)
    let engine_atom = atom.create("engine")

    let engine_pid = connect_to_engine(0, engine_node, engine_atom)

    let assert Ok(_) = mist.new(fn(req) {request_handler(req, engine_pid, create_selector())})
    |> mist.bind(self_ip)
    |> mist.start

    process.receive_forever(main_sub)
}


fn create_selector() -> process.Selector(gen_types.UserMessage) {

    process.new_selector()
    |> utls.create_selector(gen_select.get_user_selector_list())
    //|> process.select_map(sub, fn(msg) {msg})
}
