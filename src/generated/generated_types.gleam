pub type Post {

	Post(
		title: String,
		body: String
	)

}

pub type EngineMessage {

	CreatePost(
		subreddit_name: Post,
		sender_uuid: String,
		sender_pid: String
	)

	CreateSubreddit(
		subreddit_name: Post,
		sender_uuid: String,
		sender_pid: String
	)

	JoinSubreddit(
		subreddit_name: Post,
		sender_uuid: String,
		sender_pid: String
	)

	RegisterUser(
		username: String,
		sender_pid: String,
		password: String
	)
}

pub type UserMessage {

	CreatePostSuccess(
		subreddit_name: String
	)

	CreatePostFailed(
		subreddit_name: String,
		fail_reason: String
	)

	InjectCreatePost

	CreateSubredditSuccess(
		subreddit_name: String
	)

	CreateSubredditFailed(
		subreddit_name: String,
		fail_reason: String
	)

	InjectCreateSubreddit

	JoinSubredditSuccess(
		subreddit_name: String
	)

	JoinSubredditFailed(
		subreddit_name: String,
		fail_reason: String
	)

	InjectJoinSubreddit

	RegisterUserSuccess(
		subreddit_name: String
	)

	RegisterUserFailed(
		subreddit_name: String,
		fail_reason: String
	)

	InjectRegisterUser
}

