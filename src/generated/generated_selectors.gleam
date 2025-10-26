import gleam/dynamic/decode
import gleam/dynamic
import gleam/result
import generated/generated_types

import generated/generated_decoders

pub fn create_post_selector(
	data: dynamic.Dynamic
	) -> generated_types.EngineMessage {

	let res = {

		use subreddit_name <- result.try(decode.run(data, decode.at([3], generated_decoders.post_decoder())))
		use sender_uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
		use sender_pid <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(subreddit_name, sender_uuid, sender_pid))
	}

	case res {

		Ok(#(subreddit_name, sender_uuid, sender_pid)) -> {

			generated_types.CreatePost(subreddit_name, sender_uuid, sender_pid)
		}

		Error(_) -> {

			panic as "Failed to parse message register user"
		}
	}
}

pub fn create_post_success_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	case decode.run(data, decode.at([1], decode.string)) {

		Ok(name) -> {

			generated_types.CreatePostSuccess(name)
		}

		Error(_) -> {

			panic as "illegal value passed to CreatePostSuccess"
			}
		}
}

pub fn create_post_failed_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	let res = {

		use name <- result.try(decode.run(data, decode.at([2], decode.string)))
		use fail_reason <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(name, fail_reason))
	}

	case res {

		Ok(#(name, fail_reason)) -> {

			generated_types.CreatePostFailed(name, fail_reason)
		}

		Error(_) -> {

			panic as "illegal value passed to CreatePostFailed message"
		}
	}
}

//------------------------------------------------------------------

pub fn create_subreddit_selector(
	data: dynamic.Dynamic
	) -> generated_types.EngineMessage {

	let res = {

		use subreddit_name <- result.try(decode.run(data, decode.at([3], generated_decoders.post_decoder())))
		use sender_uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
		use sender_pid <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(subreddit_name, sender_uuid, sender_pid))
	}

	case res {

		Ok(#(subreddit_name, sender_uuid, sender_pid)) -> {

			generated_types.CreateSubreddit(subreddit_name, sender_uuid, sender_pid)
		}

		Error(_) -> {

			panic as "Failed to parse message register user"
		}
	}
}

pub fn create_subreddit_success_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	case decode.run(data, decode.at([1], decode.string)) {

		Ok(name) -> {

			generated_types.CreateSubredditSuccess(name)
		}

		Error(_) -> {

			panic as "illegal value passed to CreateSubredditSuccess"
			}
		}
}

pub fn create_subreddit_failed_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	let res = {

		use name <- result.try(decode.run(data, decode.at([2], decode.string)))
		use fail_reason <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(name, fail_reason))
	}

	case res {

		Ok(#(name, fail_reason)) -> {

			generated_types.CreateSubredditFailed(name, fail_reason)
		}

		Error(_) -> {

			panic as "illegal value passed to CreateSubredditFailed message"
		}
	}
}

//------------------------------------------------------------------

pub fn join_subreddit_selector(
	data: dynamic.Dynamic
	) -> generated_types.EngineMessage {

	let res = {

		use subreddit_name <- result.try(decode.run(data, decode.at([3], generated_decoders.post_decoder())))
		use sender_uuid <- result.try(decode.run(data, decode.at([2], decode.string)))
		use sender_pid <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(subreddit_name, sender_uuid, sender_pid))
	}

	case res {

		Ok(#(subreddit_name, sender_uuid, sender_pid)) -> {

			generated_types.JoinSubreddit(subreddit_name, sender_uuid, sender_pid)
		}

		Error(_) -> {

			panic as "Failed to parse message register user"
		}
	}
}

pub fn join_subreddit_success_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	case decode.run(data, decode.at([1], decode.string)) {

		Ok(name) -> {

			generated_types.JoinSubredditSuccess(name)
		}

		Error(_) -> {

			panic as "illegal value passed to JoinSubredditSuccess"
			}
		}
}

pub fn join_subreddit_failed_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	let res = {

		use name <- result.try(decode.run(data, decode.at([2], decode.string)))
		use fail_reason <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(name, fail_reason))
	}

	case res {

		Ok(#(name, fail_reason)) -> {

			generated_types.JoinSubredditFailed(name, fail_reason)
		}

		Error(_) -> {

			panic as "illegal value passed to JoinSubredditFailed message"
		}
	}
}

//------------------------------------------------------------------

pub fn register_user_selector(
	data: dynamic.Dynamic
	) -> generated_types.EngineMessage {

	let res = {

		use username <- result.try(decode.run(data, decode.at([3], decode.string)))
		use sender_pid <- result.try(decode.run(data, decode.at([2], decode.string)))
		use password <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(username, sender_pid, password))
	}

	case res {

		Ok(#(username, sender_pid, password)) -> {

			generated_types.RegisterUser(username, sender_pid, password)
		}

		Error(_) -> {

			panic as "Failed to parse message register user"
		}
	}
}

pub fn register_user_success_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	case decode.run(data, decode.at([1], decode.string)) {

		Ok(name) -> {

			generated_types.RegisterUserSuccess(name)
		}

		Error(_) -> {

			panic as "illegal value passed to RegisterUserSuccess"
			}
		}
}

pub fn register_user_failed_selector(
	data: dynamic.Dynamic
	) -> generated_types.UserMessage {

	let res = {

		use name <- result.try(decode.run(data, decode.at([2], decode.string)))
		use fail_reason <- result.try(decode.run(data, decode.at([1], decode.string)))
		Ok(#(name, fail_reason))
	}

	case res {

		Ok(#(name, fail_reason)) -> {

			generated_types.RegisterUserFailed(name, fail_reason)
		}

		Error(_) -> {

			panic as "illegal value passed to RegisterUserFailed message"
		}
	}
}