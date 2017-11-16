(**************************************************************************)
(*                                                                        *)
(*   Typerex Libraries                                                    *)
(*                                                                        *)
(*   Copyright 2011-2017 OCamlPro SAS                                     *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Cmdliner

module Types = struct

  type env = Cmdliner.Term.env_info
  type info = (string list -> Cmdliner.Arg.info)

  type spec =
    | Bool of (bool -> unit)
    | Set of bool ref
    | Clear of bool ref
    | Int of (int -> unit)
    | String of (string -> unit)
    | Strings of (string list -> unit)
    | File of (string -> unit)
    | Files of (string list -> unit)
    | Anon of int * (string -> unit)
    | Anons of (string list -> unit)

  type command = {
      cmd_name : string;
      cmd_action : (unit -> unit);
      cmd_args : (string list * spec * info) list;
      cmd_man : Cmdliner.Manpage.block list;
      cmd_doc : string;
    }
end

open Types

let info ?docs ?docv ?env doc =
  Arg.info ?docs ?docv ?env ~doc

let env = Term.env_info

let rec term_of_list list =
  match list with
  | [] -> Term.(const ())
  | (args, action, info) :: tail ->
     let x = term_of_list tail in
     let arg_info = info args in
     match action with
     | Bool f ->
        let term = Arg.(value & flag & arg_info) in
        let f () x = f x in
        Term.(const f $ x $ term)
     | Set r ->
        let term = Arg.(value & flag & arg_info) in
        let f () x = if x then r := true in
        Term.(const f $ x $ term)
     | Clear r ->
        let term = Arg.(value & flag & arg_info) in
        let f () x = if x then r := false in
        Term.(const f $ x $ term)
     | Int f ->
        let term = Arg.(value & opt (some int) None & arg_info) in
        let f () = function
          | None -> ()
          | Some s -> f s
        in
        Term.(const f $ x $ term)
     | File f ->
        let term = Arg.(value & opt (some file) None & arg_info) in
        let f () = function
          | None -> ()
          | Some s -> f s
        in
        Term.(const f $ x $ term)
     | Files f ->
        let term = Arg.(value & opt_all file [] & arg_info) in
        let f () x = f x in
        Term.(const f $ x $ term)
     | String f ->
        let term = Arg.(value & opt (some string) None & arg_info) in
        let f () = function
          | None -> ()
          | Some s -> f s
        in
        Term.(const f $ x $ term)
     | Strings f ->
        let term = Arg.(value & opt_all string [] & arg_info) in
        let f () x = f x in
        Term.(const f $ x $ term)
     | Anon (n, f) ->
        let term = Arg.(value & pos n (some string) None & arg_info) in
        let f () = function
          | None -> ()
          | Some s -> f s
        in
        Term.(const f $ x $ term)
     | Anons f ->
        let term = Arg.(value & pos_all string [] & arg_info) in
        let f () x = f x in
        Term.(const f $ x $ term)


let cmd_exits = Term.default_exits

let create_sub ?version sub =
  let man = sub.cmd_man in
  let exits = cmd_exits in
  let doc = sub.cmd_doc in
  Term.(const sub.cmd_action $ term_of_list sub.cmd_args),
  Term.info sub.cmd_name ?version ~doc
            ~sdocs:Manpage.s_common_options ~exits ~man

let help more_topics man_format cmds topic = match topic with
  | None -> `Help (`Pager, None) (* help about the program. *)
  | Some topic ->
     let topics = "topics" ::
                    List.map fst more_topics
                  @ cmds in
     let conv, _ = Cmdliner.Arg.enum (List.rev_map (fun s -> (s, s)) topics) in
     match conv topic with
     | `Error e -> `Error (false, e)
     | `Ok t when t = "topics" -> List.iter print_endline topics; `Ok ()
     | `Ok t when List.mem t cmds -> `Help (man_format, Some t)
     | `Ok t ->
        let page = (topic, 7, "", "", ""),
                   (`S topic) :: List.assoc t more_topics in
        `Ok (Cmdliner.Manpage.print man_format Format.std_formatter page)

let help_cmd ~name ~man ~topics =
  let topic =
    let doc = "The topic to get help on. `topics' lists the topics." in
    Arg.(value & pos 0 (some string) None & info [] ~docv:"TOPIC" ~doc)
  in
  let doc =
    Printf.sprintf "display help about %s and %s commands"
                   name name
  in
  let man =
    [`S Manpage.s_description;
     `P "Prints help about darcs commands and other subjects...";
     `Blocks man; ]
  in
  Term.(ret
          (const (help topics) $ Arg.man_format $ Term.choice_names $topic)),
  Term.info "help" ~doc ~exits:Term.default_exits ~man

let default_cmd ~name ?version ~doc ~man =
  let sdocs = Manpage.s_common_options in
  let exits = Term.default_exits in
  Term.(ret (const (`Help (`Pager, None)))),
  Term.info name ?version ~doc ~sdocs ~exits ~man

let main_with_subcommands ~name ?version ?default
                          ~doc ~man ?(topics = []) subs =
  let cmds = List.map (create_sub ?version) subs in
  let default_cmd = match default with
    | None ->
       default_cmd ~name ?version ~doc ~man
    | Some cmd -> create_sub ?version cmd
  in
  let cmds = cmds @ [help_cmd ~name ~man ~topics] in
  match Term.eval_choice default_cmd cmds with
  | `Ok () -> ()
  | t -> Term.exit t

let main ?version cmd =
  let cmd = create_sub ?version cmd in
  match Term.eval cmd with
  | `Ok () -> ()
  | t -> Term.exit t

module Modules = struct

  type block =
    [ `S of string | `P of string | `Pre of string | `I of string * string
      | `Noblank | `Blocks of block list ]

  module Manpage = Cmdliner.Manpage

  module Arg = struct

    include Types

    let parse ?name ?version ?(man = []) arg_list arg_anon arg_usage =
      let cmd_args =
        List.map (fun (arg, spec, doc) ->
            let len = String.length arg in
            let arg =
              if len > 0 && arg.[0] = '-' then
                if len > 1 && arg.[1] = '-' then
                  String.sub arg 2 (len-2)
                else
                  String.sub arg 1 (len-1)
              else
                arg
            in
            [arg], spec, info doc
          ) arg_list
        @
          [
            [], Anons (fun list ->
                    List.iter arg_anon list), info "General arguments"
          ]
      in
      let cmd_name = match name with
          None -> "COMMAND"
        | Some cmd_name -> cmd_name in
      let cmd = {
          cmd_name;
          cmd_doc = arg_usage;
          cmd_args;
          cmd_man = man;
          cmd_action = (fun () -> ());
        } in
      main ?version cmd

  end

end
