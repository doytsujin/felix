open Flx_bsym
open Flx_bsym_table
open Flx_bbdcl
open Flx_bid
open Flx_bexe
open Flx_bexpr
open Flx_btype
open Flx_fairy

let debug = 
  try let _ = Sys.getenv "FLX_COMPILER_DEBUG_UNIQ" in true  
  with Not_found -> false 

let show_getset_only = 
  try let _ = Sys.getenv "FLX_COMPILER_DEBUG_UNIQ_GETSET" in true  
  with Not_found -> false 


let show_getset = debug || show_getset_only
 
(* This routine finds all the indexes of uniq expressions .. well
at the moment this is just uniq variables and constant projections
of variables to uniq components
*)

exception DuplicateGet of int * path_t

let rec find_once bsym_table (chain2ix:chain2ix_t) path (b:BidSet.t ref) e : unit =
(*
print_endline ("Find once for expresssion " ^ Flx_print.sbe bsym_table e);
*)
  match e with
  | BEXPR_varname (i,_),_ -> 
    let prefix = List.rev path in
    List.iter  (fun ((j,path),ix) ->
      if j = i then
        if Flx_list.has_prefix prefix path then 
          begin
            if BidSet.mem ix !b then raise (DuplicateGet (i,path))
            else b := BidSet.add ix !b
          end
      )
    chain2ix

  | BEXPR_apply ( (BEXPR_prj (n,_,_),_), base ),_ ->
    let path = `Tup n :: path in
    find_once bsym_table chain2ix path b base 

  | x -> Flx_bexpr.flat_iter ~f_bexpr:(find_once bsym_table chain2ix path b) x

exception DuplicateSet of int * path_t

let rec find_ponce bsym_table (chain2ix:chain2ix_t) path (b:BidSet.t ref) e : unit =
(*
print_endline ("Find pointers to once for expresssion " ^ Flx_print.sbe bsym_table e);
*)
  match e with
  | BEXPR_wref (i,_),_  
  | BEXPR_ref (i,_),_ -> 
    let prefix = List.rev path in
    List.iter  (fun ((j,path),ix) ->
      if j = i then
        if Flx_list.has_prefix prefix path then 
          begin
            if BidSet.mem ix !b then raise (DuplicateSet (i,path))
            else b := BidSet.add ix !b;
          end
      )
    chain2ix

  | BEXPR_apply ( (BEXPR_prj (n,_,_),_), base ),_ ->
    let path = `Tup n :: path in
    find_ponce bsym_table chain2ix path b base 

  | x -> Flx_bexpr.flat_iter ~f_bexpr:(find_ponce bsym_table chain2ix path b) x



(* Get and Set detectors for instructions *)

let get_sets bsym_table chain2ix ix2chain bexe =
  let bidset = ref BidSet.empty in
  let f_bexpr e = 
    try find_once bsym_table chain2ix [] bidset e 
    with DuplicateGet (i,ix) ->
      print_endline ("Flx_once: Duplicate Get " ^ id_of_index bsym_table i ^" in "^Flx_print.sbe bsym_table e);
      print_endline ("Instruction " ^ Flx_print.string_of_bexe bsym_table 0 bexe); 
      let sr = Flx_bexe.get_srcref bexe in
      print_endline (Flx_srcref.long_string_of_src sr);
      failwith ("Flx_once: Duplicate Get of unique variable")
  in
  begin match bexe with 
  | BEXE_assign (_,l,_) -> f_bexpr l
  | BEXE_init (_,i,(_,vt as e)) -> f_bexpr (bexpr_varname vt (i,[]))
  | BEXE_storeat (_,l,r) -> 
    begin try
      find_ponce bsym_table chain2ix [] bidset l
    with DuplicateSet (i,ix) ->
      print_endline ("Flx_once: Duplicate Set " ^ id_of_index bsym_table i ^" in "^ Flx_print.string_of_bexe bsym_table 0 bexe);
      print_endline ("Instruction " ^ Flx_print.string_of_bexe bsym_table 0 bexe); 
      let sr = Flx_bexe.get_srcref bexe in
      print_endline (Flx_srcref.long_string_of_src sr);
      failwith ("Flx_once: Duplicate Set of unique variable")
    end
  | _ ->  () 
  end;

  if show_getset && not (BidSet.is_empty (!bidset)) then
    print_endline ("  SETS: " ^ string_of_vars bsym_table ix2chain (!bidset));
  !bidset

let get_gets bsym_table chain2ix ix2chain bexe = 
  let bidset = ref BidSet.empty in
  let f_bexpr e = 
     match e with
     | BEXPR_ref (i,_),_ -> ()
     | _ -> 
       try find_once bsym_table chain2ix [] bidset e 
       with DuplicateGet (i,ix) ->
        print_endline ("Flx_once: Duplicate Get variable " ^id_of_index bsym_table i  ^" in "^Flx_print.sbe bsym_table e);
        print_endline ("Instruction " ^ Flx_print.string_of_bexe bsym_table 0 bexe); 
        let sr = Flx_bexe.get_srcref bexe in
        print_endline (Flx_srcref.long_string_of_src sr);
        failwith ("Flx_once: Duplicate Get of unique variable")
  in
  begin match bexe with 
  (* storing at a pointer is still a get on the pointer! *)
  | BEXE_storeat (_,l,e)  -> f_bexpr l; f_bexpr e

  (* if the target of an assignment is a variable, is not a get *)
  | BEXE_assign (_,(BEXPR_varname _,_),e) 
  | BEXE_assign (_,(BEXPR_deref (BEXPR_varname _,_),_),e) 

  (* nor is the target of an initialisation *)
  | BEXE_init (_,_,e) -> f_bexpr e
  | _ -> Flx_bexe.iter ~f_bexpr bexe
  end;

  if show_getset && not (BidSet.is_empty (!bidset)) then
    print_endline ("  GETS: " ^ string_of_vars bsym_table ix2chain (!bidset));
  !bidset

(* Full unravelling removes expressions from instructions so all arguments
are variables, inserting assignments to temporaries before the instruction.
All such assignments are then either assigning a constant or variable,
or assigning the result of a single application to a constant or variable.

We have to do a partial unravel because the flow algorithm cannot remember
where control is up to during expression evaluation. However an assignment
to a variable of an application is more or less equivalent to a procedure
call. In other words the serialisation provides locations in the control
flow path allowing the algorithm to keep track of the current continuation
and liveness.

Unravelling of compositions is sound due to eager evaluation. 
However unravelling of products is only sound for unique variables
not shared ones. The reason is: two reads on a unique variable
can occur in a product; if the initial state is dead, its an error.
If the initial state is live, the first read changes it to dead,
which causes the second read to fail with an error.


*)


(* Bottom up analysis pushes innermost expression temporaries first
so the resulting list head is the outermost application. This is the order
we want because we construct the modified executable list by parsing
the list from the head, producing a list in reverse order and inserting
the already backwards temporary assignments first, then the stripped
instruction.
*)

let rec unrav sr counter extra e = 
  match Flx_bexpr.map ~f_bexpr:(unrav sr counter extra) e with
  | (BEXPR_apply ((BEXPR_closure (fidx, ts),_), (_,argt as arg)),rt as rhs) 
  | (BEXPR_apply_stack (fidx, ts, (_,argt as arg)),rt as rhs)
  | (BEXPR_apply_direct (fidx, ts, (_,argt as arg)),rt as rhs)
  ->
    let v = !counter in (* new temporary index *)
    incr counter;
    let lhs = bexpr_varname rt (v,ts) in
    let instr = bexe_assign (sr, lhs, rhs) in
    extra := instr :: !extra;
    lhs  (* return variable *)
  | x -> x

let unravel sr counter e = 
  let extra = ref [] in
  let x = unrav sr counter extra e in
  List.rev !extra, x

(* test case only, later do more instructions *)
let unravel_exe bsym_table counter exe =
  match exe with
  | BEXE_fun_return (sr,e) -> 
(* print_endline ("Unravelling return " ^ Flx_print.string_of_bexe bsym_table 2 exe); *)
    let extra,x = unravel sr counter e in
    let result = bexe_fun_return (sr,x) :: extra in
(*
    if List.length result > 1 then
    begin
      print_endline ("Unravlled function return: " ^ Flx_print.string_of_bexe bsym_table 2 exe);
      let r = List.rev result in
      List.iter (fun exe -> print_endline (Flx_print.string_of_bexe bsym_table 3 exe)) r
    end;
*)
    result
 
  | _ -> [exe]

let unravel_exes bsym_table counter exes =
   let exe_chunks = List.rev_map (unravel_exe bsym_table counter) exes in
   let rexes = List.concat exe_chunks in
   List.rev rexes


type once_data_t = {gets: BidSet.t; sets: BidSet.t}
type augexe_t = Flx_bexe.t * once_data_t 


(* Augment exes with gets and sets *)
let make_augexes bsym_table counter chain2ix ix2chain get_sets get_gets bexes : augexe_t list=
  let bexes = unravel_exes bsym_table counter bexes in
  List.map 
  (
    fun bexe -> 
      if show_getset then
        print_endline ("instruction " ^ Flx_print.string_of_bexe bsym_table 0 bexe);
      bexe, 
      {
        sets=get_sets bsym_table chain2ix ix2chain bexe; 
        gets=get_gets bsym_table chain2ix ix2chain bexe
      }
  ) 
  bexes 


