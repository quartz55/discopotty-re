type t =
  [ `Discord of string | `Http of Piaf.Error.t | `Exn of exn | `Msg of string ]

type nonrec 'a result = ('a, t) result

let of_http e = `Http e

let to_string = function
  | `Discord m -> "DiscordError: " ^ m
  | `Http piaf -> Piaf.Error.to_string piaf
  | `Exn exn -> Printexc.to_string exn
  | `Msg m -> m

let catch_lwt p = Lwt_result.(catch p |> map_err (fun exn -> `Exn exn))

let tap ~f r = function
  | Ok o -> Ok o
  | Error e ->
      f e;
      r

let tap_lwt ~f r = function
  | Ok o -> Lwt.return (Ok o)
  | Error e -> Lwt.bind (f e) (fun () -> r)
