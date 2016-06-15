open Odoc

let failwithf fmt = Printf.ksprintf failwith fmt

type t = {
  unit_of_root: Unit.t Root.Table.t ;
  expander    : Root.t DocOck.expander ;
  resolver    : Root.t DocOck.resolver ;
}

let rec find_map ~f = function
  | [] -> None
  | x :: xs ->
    match f x with
    | Some _ as res -> res
    | None -> find_map ~f xs

let root_of_unit unit =
  match unit.DocOckTypes.Unit.id with
  | DocOckPaths.Identifier.Root (root,_) -> root
  | _ -> invalid_arg "root_of_unit: not a root unit"

(* We could make this "smarter" by not listing directories whose name doesn't
   match the package name of our target.
   But that implies that package and directory names would be synchronized.
   Which seems like a strong assumption in this wild world. *)
let find_odoc_file ~directories ?digest name =
  let rec aux is_the_one = function
    | [] -> None
    | dir :: dirs ->
      let files = Fs.Directory.ls dir in
      match find_map ~f:is_the_one files with
      | None -> aux is_the_one dirs
      | res  -> res
  in
  let digest_matches =
    match digest with
    | None -> fun _ -> true
    | Some d -> fun d' -> Digest.compare d d' = 0
  in
  let target_name = (String.uncapitalize name) ^ ".odoc" in
  aux (fun file ->
    let filename = Fs.File.to_string file in
    if Filename.basename filename <> target_name then None else
    let unit = Unit.load file in
    let r = root_of_unit unit in
    if digest_matches (Root.digest r) then Some (r, unit) else None
  ) directories

type builder = Unit.t -> t

let create ?(important_digests=true) ~directories : builder = fun unit ->
  let unit_of_root = Root.Table.create 27 in
  let lookup _ target_name : Root.t DocOck.lookup_result =
    let rec aux = function
      | [] -> DocOck.Not_found
      | import :: imports ->
        match import with
        | DocOckTypes.Unit.Import.Unresolved (name, digest_opt) when name = target_name ->
          begin match digest_opt with
          | None when important_digests -> Forward_reference
          | _ ->
            match find_odoc_file ~directories target_name ?digest:digest_opt with
            | None -> Not_found
            | Some (root, unit) ->
              Root.Table.add unit_of_root root unit;
              Found root
          end
        | DocOckTypes.Unit.Import.Resolved root
          when Root.Unit.to_string (Root.unit root) = target_name ->
          begin match
            find_odoc_file ~directories target_name ~digest:(Root.digest root)
          with
          | None -> Not_found
          | Some (root, unit) ->
            Root.Table.add unit_of_root root unit;
            Found root
          end
        | _ ->
          aux imports
    in
    aux unit.DocOckTypes.Unit.imports
  in
  let fetch root : Unit.t =
    try Root.Table.find unit_of_root root
    with Not_found ->
      begin match
        find_odoc_file ~directories (Root.Unit.to_string @@ Root.unit root)
          ~digest:(Root.digest root)
      with
      | None -> failwithf "& No unit for root: %s\n%!" (Root.to_string root)
      | Some (root, unit) ->
        Root.Table.add unit_of_root root unit;
        unit
      end
  in
  let resolver = DocOck.build_resolver lookup fetch in
  let expander =
    (* CR trefis: what is the ~root param good for? *)
    let fetch ~root:_ root = fetch root in
    DocOck.build_expander fetch
  in
  { unit_of_root; expander; resolver }

let add_root_unit t unit =
  let root = root_of_unit unit in
  Root.Table.add t.unit_of_root root unit

let build builder unit =
  let t = builder unit in
  add_root_unit t unit;
  t

let resolver t = t.resolver
let expander t = t.expander
