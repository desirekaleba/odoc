open Odoc

module Digest = Digest

module Package = struct
  type t = string
  let create s = s
  let to_string s = s
end

module Unit = struct
  type t = string
  let create s = s
  let to_string s = s
end

module T = struct
  type t = {
    package : Package.t;
    unit    : Unit.t;
    digest  : Digest.t;
  }

  let digest t = t.digest

  let equal : t -> t -> bool = (=)
  let hash  : t -> int       = Hashtbl.hash
end

include T

let to_string t = t.package ^ "::" ^ t.unit

let create ~package ~unit ~digest = { package; unit; digest }

let unit t = t.unit
let package t = t.package

module Xml = struct
  let parse i =
    begin match Xmlm.input i with
    | `El_start ((_, "root_description"), _) -> ()
    | _ -> assert false
    end;
    let package = ref "" in
    let unit = ref "" in
    let digest = ref "" in
    let rec get_elt () =
      match Xmlm.input i, Xmlm.input i, Xmlm.input i with
      | `El_start ((_, name), _), `Data value, `El_end ->
        begin match name with
        | "package" -> package := value
        | "unit" -> unit := value
        | "digest" -> digest := (Digest.from_hex value)
        | _ -> assert false
        end
      | _ -> assert false
    in
    get_elt ();
    get_elt ();
    get_elt ();
    begin match Xmlm.input i with
    | `El_end -> ()
    | _ -> assert false
    end;
    create ~package:!package ~unit:!unit ~digest:!digest

  let fold =
    let make_tag name = (("", name), []) in
    let f output acc root =
      let flipped sign acc = output acc sign in
      acc
      |> flipped (`El_start (make_tag "root_description"))
      |> flipped (`El_start (make_tag "package"))
      |> flipped (`Data root.package)
      |> flipped `El_end
      |> flipped (`El_start (make_tag "unit"))
      |> flipped (`Data root.unit)
      |> flipped `El_end
      |> flipped (`El_start (make_tag "digest"))
      |> flipped (`Data (Digest.to_hex root.digest))
      |> flipped `El_end
      |> flipped `El_end
    in
    { DocOckXmlFold. f }
end

module Table = Hashtbl.Make(T)
