open Containers
module D = Discord
module M = Discord_models
module Msg = M.Message

module L = (val Relog.logger ~namespace:__MODULE__ ())

module Config = struct
  type t = { token : string; prefix : string }

  let token { token; _ } = token

  let prefix { prefix; _ } = prefix

  let of_filename filename =
    match Toml.Parser.from_filename filename with
    | `Ok tbl ->
        let open Result in
        let+ token =
          Toml.Lenses.(
            get tbl (key "auth" |-- table |-- key "token" |-- string))
          |> Option.to_result_lazy (fun () ->
                 Format.asprintf "Invalid configuration: missing [auth.token]@.")
        in
        let prefix =
          Toml.Lenses.(
            get tbl (key "commands" |-- table |-- key "prefix" |-- string))
          |> Option.get_or ~default:"!"
        in
        { token; prefix }
    | `Error (_, loc) ->
        Error
          (Format.asprintf
             "Invalid TOML in configuration: @[file='%s'@] @[line=%d@] \
              @[column=%d@]@."
             filename loc.line loc.column)
end

let setup_logging () =
  let cli_fmter = Relog.Formatter.default ~color:true ~oneline:false () in
  let cli_fmt = Format.std_formatter in
  Relog.Sink.make (fun r ->
      if Relog.(Level.compare (Record.level r) Level.Debug) <= 0 then
        cli_fmter cli_fmt r
      else ())
  |> Relog.Sink.set

module Cmd = struct
  module P = struct
    open Angstrom

    let is_ws = function ' ' | '\t' | '\n' -> true | _ -> false

    let ws = skip_while is_ws

    let cmd prefix =
      let* name = ws *> string prefix *> take_till is_ws <* ws in
      let+ args = many any_char <* end_of_input >>| String.of_list in
      (name, args)
  end

  let parse = Angstrom.parse_string ~consume:Angstrom.Consume.All

  let of_message ~prefix msg =
    match parse (P.cmd prefix) msg with Error _ -> None | Ok cmd -> Some cmd
end

let handler cfg client =
  let prefix = Config.prefix cfg in
  Sys.set_signal Sys.sigint
    (Sys.Signal_handle (fun _ -> D.Client.disconnect client));
  function
  | D.Events.MessageCreate { content; channel_id; _ } -> (
      L.warn (fun m -> m "MESSAGE: %s" content);
      match Cmd.of_message ~prefix content with
      | None -> ()
      | Some ("ping", args) ->
          let msg = Format.asprintf "**pong** %s" args in
          D.Client.send_message channel_id msg client
      | Some ("suicide", _args) ->
          let msg =
            Msg.fmt "⚠️ @{<b>@{<i>disconnecting by user request...@}@} 👋"
          in
          D.Client.send_message channel_id msg client;
          D.Client.disconnect client
      | Some (other, _) ->
          let msg =
            Msg.fmt "🛑 @{<b>unsupported command@} @{<code>%s@}" other
          in
          D.Client.send_message channel_id msg client)
  | _ -> ()

let () =
  let inner () =
    let open Result.Infix in
    setup_logging ();
    let* config = Config.of_filename "./discopotty.toml" in
    let token = Config.token config in
    Lwt_main.run (D.Client.create ~handler:(handler config) token)
    |> Result.map_err D.Error.to_string
  in
  match inner () with
  | Ok () -> ()
  | Error error -> prerr_endline ("Error: " ^ error)