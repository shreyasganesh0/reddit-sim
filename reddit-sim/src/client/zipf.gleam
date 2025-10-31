import gleam/int
import gleam/list
import gleam/float
import gleam/erlang/process
import generated/generated_types as gen_types

pub fn create_cdf(n: Int) -> List(Float) {

    let sum = 0.0
    let w_list = []
    let #(harmonic_sum, w_list) = list.range(1, n)
    |>list.fold(
        #(sum, w_list),
        fn(acc, a) {
            let #(sum, w_list) = acc
            let w = 1.0 /.int.to_float(a)
            #(sum +. w, [w, ..w_list])
        }
    )
    let ans = []
    w_list
    |> list.fold(
        ans,
        fn(acc, a) {

            [a /. harmonic_sum, ..acc]
        }   
       )
}


pub fn sample_zipf(cdf: List(Float)) -> Int {

    let r = float.random()
    let len = list.length(cdf)
    let ans = 1
    let #(_, ans) = list.fold( 
        cdf,
        #(len, ans),
        fn(acc, a) {

            let #(len, _) = acc
            case a >. r {

                True -> #(len, len)

                False -> acc
            }
        }
    )

    ans
}

pub fn create_subreddits_list(
    n: Int,
    sub: process.Subject(gen_types.UserMessage)) {

    process.send(sub, gen_types.InjectRegisterUser)
    list.range(1, n)
    |> list.each(
        fn(_a) {
            process.send(sub, gen_types.InjectCreateSubreddit) 
        }
    )
}
