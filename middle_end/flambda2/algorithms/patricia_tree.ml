(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*           Mark Shinwell and Leo White, Jane Street Europe              *)
(*                                                                        *)
(*   Copyright 2015--2020 Jane Street Group LLC                           *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

[@@@ocaml.warning "+a-4-30-40-41-42"]

open! Int_replace_polymorphic_compare

(* CR mshinwell: Add a [compare] value to the functor argument and use it to
   sort the results from [elements], [bindings] etc? *)

(* The following is a "little endian" implementation. *)

(* CR mshinwell: Can we fix the traversal order by swapping endianness? What
   other (dis)advantages might that have? *)

let zero_bit i bit = i land bit = 0

let lowest_bit x = x land -x

let branching_bit prefix0 prefix1 = lowest_bit (prefix0 lxor prefix1)

let mask i bit = i land (bit - 1)

let match_prefix i prefix bit = mask i bit = prefix

let equal_prefix prefix0 bit0 prefix1 bit1 = bit0 = bit1 && prefix0 = prefix1

let shorter bit0 bit1 =
  match bit0 < 0, bit1 < 0 with
  | false, false -> bit0 < bit1
  | true, false | false, true -> bit0 > bit1
  | true, true -> assert false

let includes_prefix prefix0 bit0 prefix1 bit1 =
  shorter bit0 bit1 && match_prefix prefix1 prefix0 bit0

(* let includes_prefix prefix0 bit0 prefix1 bit1 = (bit0 - 1) < (bit1 - 1) &&
   match_prefix prefix1 prefix0 bit0 *)

let compare_prefix prefix0 bit0 prefix1 bit1 =
  let c = compare bit0 bit1 in
  if c = 0 then compare prefix0 prefix1 else c

type key = int

module type Tree = sig
  type 'a t

  (* A witness that ['a] is a valid type for a value stored in the tree. Maps
     will allow ['a] to be any value but sets will only allow [unit]. *)
  type 'a is_value [@@immediate]

  (* Deduce that ['a] is a value type from a pre-existing ['a t]. *)
  val is_value_of : 'a t -> 'a is_value

  val empty : 'a is_value -> 'a t

  val leaf : 'a is_value -> key -> 'a -> 'a t

  val branch : key -> key -> 'a t -> 'a t -> 'a t

  type 'a descr =
    | Empty
    | Leaf of key * 'a
    | Branch of key * key * 'a t * 'a t

  val descr : 'a t -> 'a descr

  module Binding : sig
    type 'a t

    val create : key -> 'a -> 'a t

    val key : _ t -> key

    val value : 'a is_value -> 'a t -> 'a
  end

  module Callback : sig
    type ('a, 'b) t

    val of_func : 'a is_value -> (key -> 'a -> 'b) -> ('a, 'b) t

    val call : ('a, 'b) t -> key -> 'a -> 'b
  end
end

module Set0 = struct
  type 'a t =
    | Empty : unit t
    | Leaf : key -> unit t
    | Branch : key * key * unit t * unit t -> unit t

  type 'a is_value = Unit : unit is_value

  let[@inline always] is_value_of (type a) (t : a t) : a is_value =
    (* Crucially, this compiles down to just [Unit], making this function cost
       nothing. *)
    match t with Empty -> Unit | Leaf _ -> Unit | Branch _ -> Unit

  let[@inline always] empty (type a) (Unit : a is_value) : a t = Empty

  let[@inline always] leaf (type a) (Unit : a is_value) elt (() : a) : a t =
    Leaf elt

  let[@inline always] branch (type a) prefix bit (t0 : a t) (t1 : a t) : a t =
    let Unit = is_value_of t0 in
    Branch (prefix, bit, t0, t1)

  type 'a descr =
    | Empty
    | Leaf of key * 'a
    | Branch of key * key * 'a t * 'a t

  let descr (type a) : a t -> a descr = function
    | Empty -> Empty
    | Leaf elt -> Leaf (elt, ())
    | Branch (prefix, bit, t0, t1) -> Branch (prefix, bit, t0, t1)

  module Binding = struct
    type _ t = key

    let[@inline always] create i _ = i

    let[@inline always] key i = i

    let[@inline always] value (type a) (Unit : a is_value) (_i : a t) : a = ()
  end

  module Callback = struct
    type (_, 'b) t = key -> 'b

    let[@inline always] of_func (type a) (Unit : a is_value)
        (f : key -> a -> 'b) key =
      (f [@inlined hint]) key ()

    let[@inline always] call f key _ = f key
  end
end

module _ : Tree = Set0

module Map0 = struct
  type 'a t =
    | Empty
    | Leaf of key * 'a
    | Branch of key * key * 'a t * 'a t

  type _ is_value = Any : 'a is_value

  let[@inline always] is_value_of _ = Any

  let[@inline always] empty Any = Empty

  let[@inline always] leaf Any i d = Leaf (i, d)

  let[@inline always] branch prefix bit t0 t1 = Branch (prefix, bit, t0, t1)

  type 'a descr = 'a t =
    | Empty
    | Leaf of key * 'a
    | Branch of key * key * 'a t * 'a t

  let descr = Fun.id

  module Binding = struct
    type 'a t = key * 'a

    let[@inline always] create i d = i, d

    let[@inline always] key (i, _d) = i

    let[@inline always] value Any (_i, d) = d
  end

  module Callback = struct
    type ('a, 'b) t = key -> 'a -> 'b

    let[@inline always] call f i d = f i d

    let[@inline always] of_func Any f = f
  end
end

module _ : Tree = Map0

module Tree_operations (Tree : Tree) : sig
  open! Tree

  val is_empty : 'a t -> bool

  val singleton : 'a is_value -> key -> 'a -> 'a t

  val mem : key -> 'a t -> bool

  val add : key -> 'a -> 'a t -> 'a t

  val replace : key -> ('a -> 'a) -> 'a t -> 'a t

  val update : key -> ('a option -> 'a option) -> 'a t -> 'a t

  val remove : key -> 'a t -> 'a t

  val union : (key -> 'a -> 'a -> 'a option) -> 'a t -> 'a t -> 'a t

  val subset : 'a t -> 'a t -> bool

  val find : key -> 'a t -> 'a

  val inter : 'c is_value -> (key -> 'a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t

  val inter_domain_is_non_empty : 'a t -> 'b t -> bool

  val diff : 'a t -> 'b t -> 'a t

  val cardinal : _ t -> int

  val iter : ('a, unit) Callback.t -> 'a t -> unit

  val fold : ('a, 'b -> 'b) Callback.t -> 'a t -> 'b -> 'b

  val for_all : ('a, bool) Callback.t -> 'a t -> bool

  val exists : ('a, bool) Callback.t -> 'a t -> bool

  val filter : ('a, bool) Callback.t -> 'a t -> 'a t

  val partition : ('a, bool) Callback.t -> 'a t -> 'a t * 'a t

  val choose : 'a t -> 'a Binding.t

  val choose_opt : 'a t -> 'a Binding.t option

  val min_binding : 'a t -> 'a Binding.t

  val min_binding_opt : 'a t -> 'a Binding.t option

  val max_binding : 'a t -> 'a Binding.t

  val max_binding_opt : 'a t -> 'a Binding.t option

  val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool

  val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int

  val split :
    found:('a -> 'b) -> not_found:'b -> key -> 'a t -> 'a t * 'b * 'a t

  val to_list_unordered : 'a t -> 'a Binding.t list

  val merge :
    'c is_value ->
    (key -> 'a option -> 'b option -> 'c option) ->
    'a t ->
    'b t ->
    'c t

  val find_opt : key -> 'a t -> 'a option

  val get_singleton : 'a t -> 'a Binding.t option

  val map : 'b is_value -> ('a -> 'b) -> 'a t -> 'b t

  val map_sharing : ('a -> 'a) -> 'a t -> 'a t

  val mapi : 'b is_value -> ('a, 'b) Callback.t -> 'a t -> 'b t

  val to_seq : 'a t -> 'a Binding.t Seq.t

  val of_list : 'a is_value -> 'a Binding.t list -> 'a t

  val disjoint_union :
    ?eq:('a -> 'a -> bool) ->
    print:(Format.formatter -> key -> unit) ->
    'a t ->
    'a t ->
    'a t

  val map_keys : (key -> key) -> 'a t -> 'a t
end = struct
  include Tree

  let branch prefix bit t0 t1 =
    match (descr [@inlined hint]) t0, (descr [@inlined hint]) t1 with
    | Empty, _ -> t1
    | _, Empty -> t0
    | _, _ -> Tree.branch prefix bit t0 t1
    [@@inline always]

  let branch_non_empty prefix bit t0 t1 =
    (Tree.branch [@inlined hint]) prefix bit t0 t1
    [@@inline always]

  let is_empty t =
    match descr t with Empty -> true | Leaf _ -> false | Branch _ -> false

  let singleton iv i d = leaf iv i d

  let rec mem i t =
    match descr t with
    | Empty -> false
    | Leaf (j, _) -> j = i
    | Branch (prefix, bit, t0, t1) ->
      if not (match_prefix i prefix bit)
      then false
      else if zero_bit i bit
      then mem i t0
      else mem i t1

  let join prefix0 t0 prefix1 t1 =
    let bit = branching_bit prefix0 prefix1 in
    if zero_bit prefix0 bit
    then branch (mask prefix0 bit) bit t0 t1
    else branch (mask prefix0 bit) bit t1 t0

  (* CR mshinwell: This is now [add_or_replace], like [Map] *)
  let rec add i d t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> leaf iv i d
    | Leaf (j, _) -> if i = j then leaf iv i d else join i (leaf iv i d) j t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch_non_empty prefix bit (add i d t0) t1
        else branch_non_empty prefix bit t0 (add i d t1)
      else join i (leaf iv i d) prefix t

  let rec replace key f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> empty iv
    | Leaf (key', datum) ->
      if key = key'
      then
        let datum = f datum in
        leaf iv key datum
      else t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix key prefix bit
      then
        if zero_bit key bit
        then branch_non_empty prefix bit (replace key f t0) t1
        else branch_non_empty prefix bit t0 (replace key f t1)
      else t

  let rec update key f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> begin
      match f None with None -> empty iv | Some datum -> leaf iv key datum
    end
    | Leaf (key', datum) -> (
      if key = key'
      then
        match f (Some datum) with
        | None -> empty iv
        | Some datum -> leaf iv key datum
      else
        match f None with
        | None -> t
        | Some datum -> join key (leaf iv key datum) key' t)
    | Branch (prefix, bit, t0, t1) -> (
      if match_prefix key prefix bit
      then
        if zero_bit key bit
        then branch prefix bit (update key f t0) t1
        else branch prefix bit t0 (update key f t1)
      else
        match f None with
        | None -> t
        | Some datum -> join key (leaf iv key datum) prefix t)

  let rec remove i t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> empty iv
    | Leaf (j, _) -> if i = j then empty iv else t
    | Branch (prefix, bit, t0, t1) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch prefix bit (remove i t0) t1
        else branch prefix bit t0 (remove i t1)
      else t

  (* CR mshinwell: Provide a [union] where [f] doesn't return an [option]. *)
  (* CR pchambart: union x x is expensive, while it could be O(1). This would
     require that we demand f x x = x *)
  let rec union f t0 t1 =
    let iv = is_value_of t0 in
    match descr t0, descr t1 with
    | Empty, _ -> t1
    | _, Empty -> t0
    | Leaf (i, d0), Leaf (j, d1) when i = j -> begin
      (* CR mshinwell: [join] in [Typing_env_level] is relying on the fact that
         the arguments to [f] are always in the correct order, i.e. that the
         first datum comes from [t0] and the second from [t1]. Document. *)
      match f i d0 d1 with None -> empty iv | Some datum -> leaf iv i datum
    end
    | Leaf (i, d0), Leaf (j, _) -> join i (leaf iv i d0) j t1
    | Leaf (i, d), Branch (prefix, bit, t10, t11) ->
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then branch prefix bit (union f t0 t10) t11
        else branch prefix bit t10 (union f t0 t11)
      else join i (leaf iv i d) prefix t1
    | Branch (prefix, bit, t00, t01), Leaf (i, d) ->
      if match_prefix i prefix bit
      then
        let f i d0 d1 = f i d1 d0 in
        (* CR mshinwell: add flag to disable? *)
        if zero_bit i bit
        then branch prefix bit (union f t1 t00) t01
        else branch prefix bit t00 (union f t1 t01)
      else join i (leaf iv i d) prefix t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (union f t00 t10) (union f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then branch prefix0 bit0 (union f t00 t1) t01
        else branch prefix0 bit0 t00 (union f t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then branch prefix1 bit1 (union f t0 t10) t11
        else branch prefix1 bit1 t10 (union f t0 t11)
      else join prefix0 t0 prefix1 t1

  (* CR mshinwell: rename to subset_domain and inter_domain? *)

  let rec subset t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ -> true
    | _, Empty -> false
    | Branch _, Leaf _ -> false
    | Leaf (i, _), _ -> mem i t1
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then subset t00 t10 && subset t01 t11
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then if zero_bit prefix0 bit1 then subset t0 t10 else subset t0 t11
      else false

  let rec find i t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (j, d) -> if j = i then d else raise Not_found
    | Branch (prefix, bit, t0, t1) ->
      if not (match_prefix i prefix bit)
      then raise Not_found
      else if zero_bit i bit
      then find i t0
      else find i t1

  let rec inter iv f t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ -> empty iv
    | _, Empty -> empty iv
    | Leaf (i, d0), _ -> begin
      match find i t1 with
      | exception Not_found -> empty iv
      | d1 -> leaf iv i (f i d0 d1)
    end
    | _, Leaf (i, d1) -> begin
      match find i t0 with
      | exception Not_found -> empty iv
      | d0 -> leaf iv i (f i d0 d1)
    end
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (inter iv f t00 t10) (inter iv f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0 then inter iv f t00 t1 else inter iv f t01 t1
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1 then inter iv f t0 t10 else inter iv f t0 t11
      else empty iv

  let rec inter_domain_is_non_empty t0 t1 =
    match descr t0, descr t1 with
    | Empty, _ | _, Empty -> false
    | Leaf (i, _), _ -> mem i t1
    | _, Leaf (i, _) -> mem i t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then
        inter_domain_is_non_empty t00 t10 || inter_domain_is_non_empty t01 t11
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then inter_domain_is_non_empty t00 t1
        else inter_domain_is_non_empty t01 t1
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then inter_domain_is_non_empty t0 t10
        else inter_domain_is_non_empty t0 t11
      else false

  let rec diff t0 t1 =
    let iv = is_value_of t0 in
    match descr t0, descr t1 with
    | Empty, _ -> empty iv
    | _, Empty -> t0
    | Leaf (i, _), _ -> if mem i t1 then empty iv else t0
    | _, Leaf (i, _) -> remove i t0
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (diff t00 t10) (diff t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then branch prefix0 bit0 (diff t00 t1) t01
        else branch prefix0 bit0 t00 (diff t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then if zero_bit prefix0 bit1 then diff t0 t10 else diff t0 t11
      else t0

  let rec cardinal t =
    match descr t with
    | Empty -> 0
    | Leaf _ -> 1
    | Branch (_, _, t0, t1) -> cardinal t0 + cardinal t1

  let rec iter f t =
    match descr t with
    | Empty -> ()
    | Leaf (key, d) -> Callback.call f key d
    | Branch (_, _, t0, t1) ->
      iter f t0;
      iter f t1

  let rec fold f t acc =
    match descr t with
    | Empty -> acc
    | Leaf (key, d) -> Callback.call f key d acc
    | Branch (_, _, t0, t1) -> fold f t0 (fold f t1 acc)

  let rec for_all p t =
    match descr t with
    | Empty -> true
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, _, t0, t1) -> for_all p t0 && for_all p t1

  let rec exists p t =
    match descr t with
    | Empty -> false
    | Leaf (key, d) -> Callback.call p key d
    | Branch (_, _, t0, t1) -> exists p t0 || exists p t1

  let filter p t =
    let rec loop acc t =
      match descr t with
      | Empty -> acc
      | Leaf (i, d) -> if Callback.call p i d then add i d acc else acc
      | Branch (_, _, t0, t1) -> loop (loop acc t0) t1
    in
    loop (empty (is_value_of t)) t

  let partition p t =
    let rec loop ((true_, false_) as acc) t =
      match descr t with
      | Empty -> acc
      | Leaf (i, d) ->
        if Callback.call p i d
        then add i d true_, false_
        else true_, add i d false_
      | Branch (_, _, t0, t1) -> loop (loop acc t0) t1
    in
    let empty = empty (is_value_of t) in
    loop (empty, empty) t

  let rec choose t =
    match descr t with
    | Empty -> raise Not_found
    | Leaf (key, d) -> Binding.create key d
    | Branch (_, _, t0, _) -> choose t0

  let choose_opt t =
    match choose t with exception Not_found -> None | choice -> Some choice

  let[@inline always] min_binding_by ~compare_key (t : 'a t) : 'a Binding.t =
    let rec loop t =
      match descr t with
      | Empty -> raise Not_found
      | Leaf (i, d) -> Binding.create i d
      | Branch (_, _, t0, t1) ->
        let b0 = loop t0 in
        let b1 = loop t1 in
        if (compare_key [@inlined hint]) (Binding.key b0) (Binding.key b1) < 0
        then b0
        else b1
    in
    loop t

  let min_binding t = min_binding_by ~compare_key:Int.compare t

  let min_binding_opt t =
    match min_binding t with exception Not_found -> None | min -> Some min

  let max_binding t =
    let[@inline always] compare_key i1 i2 = Int.compare i2 i1 in
    min_binding_by ~compare_key t

  let max_binding_opt t =
    match max_binding t with exception Not_found -> None | max -> Some max

  let rec equal f t0 t1 =
    if t0 == t1
    then true
    else
      match descr t0, descr t1 with
      | Empty, Empty -> true
      | Leaf (i, d0), Leaf (j, d1) -> i = j && f d0 d1
      | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
        if equal_prefix prefix0 bit0 prefix1 bit1
        then equal f t00 t10 && equal f t01 t11
        else false
      | _, _ -> false

  let rec compare f t0 t1 =
    match descr t0, descr t1 with
    | Empty, Empty -> 0
    | Leaf (i, d0), Leaf (j, d1) ->
      let c = if i = j then 0 else if i < j then -1 else 1 in
      if c <> 0 then c else f d0 d1
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      let c = compare_prefix prefix0 bit0 prefix1 bit1 in
      if c = 0
      then
        let c = compare f t00 t10 in
        if c = 0 then compare f t01 t11 else c
      else c
    | Empty, Leaf _ -> 1
    | Empty, Branch _ -> 1
    | Leaf _, Branch _ -> 1
    | Leaf _, Empty -> -1
    | Branch _, Empty -> -1
    | Branch _, Leaf _ -> -1

  let[@inline always] split ~found ~not_found i t =
    let rec loop ((lt, mem, gt) as acc) t =
      match descr t with
      | Empty -> acc
      | Leaf (j, d) ->
        if i = j
        then lt, (found [@inlined hint]) d, gt
        else if j < i
        then add j d lt, mem, gt
        else lt, mem, add j d gt
      | Branch (_, _, t0, t1) -> loop (loop acc t0) t1
    in
    let empty = empty (is_value_of t) in
    loop (empty, not_found, empty) t

  let to_list_unordered t =
    let rec loop acc t =
      match descr t with
      | Empty -> acc
      | Leaf (i, d) -> Binding.create i d :: acc
      | Branch (_, _, t0, t1) -> loop (loop acc t0) t1
    in
    loop [] t

  (* CR lmaurer: We could borrow Haskell's trick and generalize this function
     quite a bit, giving us a single implementation of [union], [inter], etc.
     without sacrificing sharing. It also avoids passing or returning options.
     We could even turn it into a functor over three [Tree] instances and get
     arbitrary combinations of taking and returning sets and maps. *)
  let rec merge' :
      type a b c.
      c Tree.is_value ->
      (key -> a option -> b option -> c option) ->
      a t ->
      b t ->
      c t =
   fun iv f t0 t1 ->
    let iv0 = is_value_of t0 in
    let iv1 = is_value_of t1 in
    match descr t0, descr t1 with
    (* Empty cases, just recurse and be sure to call f on all leaf cases
       recursively *)
    | Empty, Empty -> empty iv
    | Empty, Leaf (i, d) -> begin
      match f i None (Some d) with None -> empty iv | Some d' -> leaf iv i d'
    end
    | Leaf (i, d), Empty -> begin
      match f i (Some d) None with None -> empty iv | Some d' -> leaf iv i d'
    end
    | Empty, Branch (prefix, bit, t10, t11) ->
      branch prefix bit (merge' iv f t0 t10) (merge' iv f t0 t11)
    | Branch (prefix, bit, t00, t01), Empty ->
      branch prefix bit (merge' iv f t00 t1) (merge' iv f t01 t1)
    (* Leaf cases *)
    | Leaf (i, d0), Leaf (j, d1) when i = j -> begin
      match f i (Some d0) (Some d1) with
      | None -> empty iv
      | Some datum -> leaf iv i datum
    end
    | Leaf (i, d0), Leaf (j, d1) -> begin
      match f i (Some d0) None, f j None (Some d1) with
      | None, None -> empty iv
      | Some d0, None -> leaf iv i d0
      | None, Some d1 -> leaf iv j d1
      | Some d0, Some d1 -> join i (leaf iv i d0) j (leaf iv j d1)
    end
    (* leaf <-> Branch cases *)
    | Leaf (i, d), Branch (prefix, bit, t10, t11) -> (
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then
          branch prefix bit (merge' iv f t0 t10) (merge' iv f (empty iv0) t11)
        else
          branch prefix bit (merge' iv f (empty iv0) t10) (merge' iv f t0 t11)
      else
        match f i (Some d) None with
        | None -> merge' iv f (empty iv0) t1
        | Some d -> join i (leaf iv i d) prefix (merge' iv f (empty iv0) t1))
    | Branch (prefix, bit, t00, t01), Leaf (i, d) -> (
      if match_prefix i prefix bit
      then
        if zero_bit i bit
        then
          branch prefix bit (merge' iv f t00 t1) (merge' iv f t01 (empty iv1))
        else
          branch prefix bit (merge' iv f t00 (empty iv1)) (merge' iv f t01 t1)
      else
        match f i None (Some d) with
        | None -> merge' iv f t0 (empty iv1)
        | Some d -> join i (leaf iv i d) prefix (merge' iv f t0 (empty iv1)))
    | Branch (prefix0, bit0, t00, t01), Branch (prefix1, bit1, t10, t11) ->
      if equal_prefix prefix0 bit0 prefix1 bit1
      then branch prefix0 bit0 (merge' iv f t00 t10) (merge' iv f t01 t11)
      else if includes_prefix prefix0 bit0 prefix1 bit1
      then
        if zero_bit prefix1 bit0
        then
          branch prefix0 bit0 (merge' iv f t00 t1) (merge' iv f t01 (empty iv1))
        else
          branch prefix0 bit0 (merge' iv f t00 (empty iv1)) (merge' iv f t01 t1)
      else if includes_prefix prefix1 bit1 prefix0 bit0
      then
        if zero_bit prefix0 bit1
        then
          branch prefix1 bit1 (merge' iv f t0 t10) (merge' iv f (empty iv0) t11)
        else
          branch prefix1 bit1 (merge' iv f (empty iv0) t10) (merge' iv f t0 t11)
      else
        join prefix0
          (merge' iv f t0 (empty iv1))
          prefix1
          (merge' iv f (empty iv0) t1)

  let find_opt t key =
    match find t key with exception Not_found -> None | datum -> Some datum

  let get_singleton t =
    match descr t with
    | Empty | Branch _ -> None
    | Leaf (key, datum) -> Some (Binding.create key datum)

  let rec map iv f t =
    match descr t with
    | Empty -> empty iv
    | Leaf (k, datum) -> leaf iv k (f datum)
    | Branch (prefix, bit, t0, t1) ->
      branch prefix bit (map iv f t0) (map iv f t1)

  let rec map_sharing f t =
    let iv = is_value_of t in
    match descr t with
    | Empty -> t
    | Leaf (k, v) ->
      let v' = f v in
      if v == v' then t else leaf iv k v'
    | Branch (prefix, bit, t0, t1) ->
      let t0' = map_sharing f t0 in
      let t1' = map_sharing f t1 in
      if t0' == t0 && t1' == t1 then t else branch prefix bit t0' t1'

  let rec mapi iv f t =
    match descr t with
    | Empty -> empty iv
    | Leaf (key, datum) -> leaf iv key (Callback.call f key datum)
    | Branch (prefix, bit, t0, t1) ->
      branch prefix bit (mapi iv f t0) (mapi iv f t1)

  let to_seq t =
    let rec aux acc () =
      match acc with
      | [] -> Seq.Nil
      | t0 :: r -> begin
        match descr t0 with
        | Empty -> aux r ()
        | Leaf (key, value) -> Seq.Cons (Binding.create key value, aux r)
        | Branch (_, _, t1, t2) -> aux (t1 :: t2 :: r) ()
      end
    in
    aux [t]

  let[@inline always] of_list iv l =
    List.fold_left
      (fun map b -> add (Binding.key b) (Binding.value iv b) map)
      (empty iv) l

  let merge f t0 t1 = merge' f t0 t1

  (* CR mshinwell: fix this *)
  let[@inline always] disjoint_union ?eq ~print t1 t2 =
    if t1 == t2
    then t1
    else
      let fail key =
        Misc.fatal_errorf
          "Patricia_tree.disjoint_union: key %a is in intersection" print key
      in
      union
        (fun key datum1 datum2 ->
          match eq with
          | None -> fail key
          | Some eq -> if eq datum1 datum2 then Some datum1 else fail key)
        t1 t2

  let map_keys f t =
    let iv = is_value_of t in
    fold (Callback.of_func iv (fun i d acc -> add (f i) d acc)) t (empty iv)
end
[@@inline always]

module Set = struct
  type elt = key

  type t = unit t0

  and 'a t0 = 'a Set0.t =
    | Empty : unit t0
    | Leaf : elt -> unit t0
    | Branch : elt * elt * unit t0 * unit t0 -> unit t0

  module Ops = Tree_operations (Set0)
  include Ops

  let empty = Empty

  let singleton i = Ops.singleton Unit i ()

  let add i t = Ops.add i () t

  (* CR lmaurer: This is slow, but [Ops.union] is hard to specialize *)
  let union t0 t1 = Ops.union (fun _ () () -> Some ()) t0 t1

  let disjoint t0 t1 = not (Ops.inter_domain_is_non_empty t0 t1)

  (* CR lmaurer: Also should probably be specialized *)
  let inter t0 t1 = Ops.inter Unit (fun _ () () -> ()) t0 t1

  let rec union_list ts =
    match ts with [] -> empty | t :: ts -> union t (union_list ts)

  let filter_map f t =
    let rec loop f acc = function
      | Empty -> acc
      | Leaf i -> begin match f i with None -> acc | Some j -> add j acc end
      | Branch (_, _, t0, t1) -> loop f (loop f acc t0) t1
    in
    loop f Empty t

  let elements = Ops.to_list_unordered

  let min_elt = Ops.min_binding

  let min_elt_opt = Ops.min_binding_opt

  let max_elt = Ops.max_binding

  let max_elt_opt = Ops.max_binding_opt

  let equal t0 t1 = Ops.equal (fun () () -> true) t0 t1

  let compare t0 t1 = Ops.compare (fun () () -> 0) t0 t1

  let split i t = Ops.split ~found:(fun () -> true) ~not_found:false i t

  let find elt t = if mem elt t then elt else raise Not_found

  let of_list l = Ops.of_list Unit l

  let map f t = Ops.map_keys f t
end

module Map = struct
  include Map0
  module Ops = Tree_operations (Map0)
  include Ops

  let empty = Empty

  let singleton i d = Ops.singleton Any i d

  let inter f t0 t1 = Ops.inter Any f t0 t1

  let split i t = Ops.split ~found:(fun a -> Some a) ~not_found:None i t

  let bindings s =
    List.sort
      (fun (id1, _) (id2, _) -> Int.compare id1 id2)
      (Ops.to_list_unordered s)

  let map f t = Ops.map Any f t

  let mapi f t = Ops.mapi Any f t

  let filter_map f t =
    fold
      (fun id v map -> match f id v with None -> map | Some r -> add id r map)
      t empty

  let of_list l = Ops.of_list Any l

  let merge f t0 t1 = Ops.merge Any f t0 t1

  (* CR lmaurer: This should be doable as a map operation if we generalize
     [Ops.map] by letting the returned tree be built by a different [Tree]
     module *)
  let keys map = fold (fun k _ set -> Set.add k set) map Set.empty

  let data t = List.map snd (bindings t)

  (* CR lmaurer: See comment on [keys] *)
  let of_set f set = Set.fold (fun e map -> add e (f e) map) set empty

  let diff_domains = diff
end

module Make (X : sig
  val print : Format.formatter -> key -> unit
end) =
struct
  module Set = struct
    include Set
    module Elt = X

    let [@ocamlformat "disable"] print ppf s =
      let elts ppf s = iter (fun e -> Format.fprintf ppf "@ %a" Elt.print e) s in
      Format.fprintf ppf "@[<1>{@[%a@ @]}@]" elts s

    let to_string s = Format.asprintf "%a" print s
  end

  module Map = struct
    include Map
    module Key = X

    type nonrec key = key

    module Set = Set

    let [@ocamlformat "disable"] print_debug print_datum ppf t =
      let rec pp ppf t =
        match t with
        | Empty -> Format.pp_print_string ppf "()"
        | Leaf (k, v) -> Format.fprintf ppf "@[<hv 1>(%x@ %a)@]" k print_datum v
        | Branch (k1, k2, l, r) ->
          Format.fprintf ppf "@[<hv 1>(branch@ %x@ %x@ %a@ %a)@]" k1 k2 pp l
            pp r
      in
      pp ppf t

    let disjoint_union ?eq ?print t1 t2 =
      ignore print;
      Ops.disjoint_union ~print:Key.print ?eq t1 t2

    let [@ocamlformat "disable"] print print_datum ppf t =
      if is_empty t then
        Format.fprintf ppf "{}"
      else
        Format.fprintf ppf "@[<hov 1>{%a}@]"
          (Format.pp_print_list ~pp_sep:Format.pp_print_space
             (fun ppf (key, datum) ->
                Format.fprintf ppf "@[<hov 1>(%a@ %a)@]"
                  Key.print key print_datum datum))
          (bindings t)
  end
end
[@@inline always]
