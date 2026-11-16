:- module units.
:- interface.
:- import_module io.
:- pred main(io::di, io::uo) is det.
:- implementation.
:- import_module int, list, string, maybe.

:- type dim ---> dim(int, int, int).
:- type quantity ---> q(dim, maybe(int), list(int)).
:- type outcome ---> passed(quantity) ; rejected(string).
:- type step ---> next(list(quantity)) ; bad(string).

main(!IO) :-
    io.open_input("validated.txt", Open, !IO),
    ( Open = error(E), finish("error.txt", io.error_message(E), !IO)
    ; Open = ok(F),
      io.read_file_as_string(F, Read, !IO), io.close_input(F, !IO),
      ( Read = error(_, E), finish("error.txt", io.error_message(E), !IO)
      ; Read = ok(Text),
        walk(string.split_at_char('\n', Text), [], Outcome),
        ( Outcome = rejected(Message), finish("error.txt", Message, !IO), io.set_exit_status(1, !IO)
        ; Outcome = passed(q(D, _, _)), D = dim(L, M, T),
          finish("units.txt", label(D) ++ "\n" ++ string.int_to_string(L) ++ " " ++ string.int_to_string(M) ++ " " ++ string.int_to_string(T), !IO)
        )
      )
    ).

:- pred finish(string::in, string::in, io::di, io::uo) is det.
finish(Name, Text, !IO) :-
    io.open_output(Name, Open, !IO),
    ( Open = ok(F), io.write_string(F, Text, !IO), io.close_output(F, !IO)
    ; Open = error(_), io.set_exit_status(1, !IO)
    ).

:- pred walk(list(string)::in, list(quantity)::in, outcome::out) is det.
walk([], Stack, Result) :-
    ( Stack = [Q] -> Result = passed(Q) ; Result = rejected("Invalid dimension stack.") ).
walk([Line | Lines], Stack, Result) :-
    Parts = string.words(Line),
    ( Parts = [] -> walk(Lines, Stack, Result)
    ; Parts = ["N", Number] ->
        ( string.to_int(Number, N) -> Value = yes(N) ; Value = no ),
        walk(Lines, [q(dim(0,0,0), Value, []) | Stack], Result)
    ; Parts = ["C", _] -> walk(Lines, [q(dim(0,0,0), no, []) | Stack], Result)
    ; Parts = ["F", Op, Arity], string.to_int(Arity, Count), take_args(Count, Stack, RevArgs, Rest) ->
        Args = list.reverse(RevArgs),
        apply(Op, Args, Checked),
        ( Checked = next(Values),
          ( Values = [q(D,V,_)], bounded(D) ->
              output_shape(Op, Args, Shape), walk(Lines, [q(D,V,Shape) | Rest], Result)
          ; Values = [_] -> Result = rejected("Unit exponents must stay between -1024 and 1024.")
          ; Result = rejected("Invalid unit result.") )
        ; Checked = bad(M), Result = rejected(M)
        )
    ; Result = rejected("Invalid instruction for unit checker.")
    ).

:- pred take_args(int::in, list(T)::in, list(T)::out, list(T)::out) is semidet.
take_args(N, All, Taken, Rest) :-
    ( N = 0 -> Taken = [], Rest = All
    ; N > 0, All = [H | Tail], take_args(N - 1, Tail, More, Rest), Taken = [H | More]
    ).

% Keep shape metadata accurate through scalar reductions and broadcasting.
% Eiffel independently checks whether each requested shape operation is valid.
:- pred output_shape(string::in, list(quantity)::in, list(int)::out) is det.
output_shape(Op, Args, Shape) :-
    ( Args = [q(_,_,A) | Tail] ->
        ( Op = "array" -> Shape = [list.length(Args) | A]
        ; list.member(Op,["dot","det","norm","sum","mean","median","min","max","variance","stdev","hypot"]) -> Shape = []
        ; Op = "transpose" -> Shape = list.reverse(A)
        ; Op = "matmul", A = [Rows,_], Tail = [q(_,_,[_,Cols])] -> Shape = [Rows,Cols]
        ; A = [], Tail = [q(_,_,B)] -> Shape = B
        ; Shape = A )
    ; Shape = [] ).

:- func add(dim, dim) = dim.
:- pred bounded(dim::in) is semidet.
bounded(dim(A,B,C)) :- A >= -1024, A =< 1024, B >= -1024, B =< 1024, C >= -1024, C =< 1024.
add(dim(A,B,C), dim(D,E,F)) = dim(A+D,B+E,C+F).
:- func scale(dim, int) = dim.
scale(dim(A,B,C), N) = dim(A*N,B*N,C*N).
:- pred same(list(quantity)::in, dim::in) is semidet.
same([], _).
same([q(D,_,_) | Tail], D) :- same(Tail,D).
:- pred unit(string::in, dim::out) is semidet.
unit("unit_m",dim(1,0,0)). unit("unit_cm",dim(1,0,0)). unit("unit_km",dim(1,0,0)).
unit("unit_s",dim(0,0,1)). unit("unit_ms",dim(0,0,1)). unit("unit_seconds",dim(0,0,1)).
unit("unit_kg",dim(0,1,0)). unit("unit_g",dim(0,1,0)).

:- pred apply(string::in, list(quantity)::in, step::out) is det.
apply(Op, Args, Result) :-
    ( Args = [q(A, V, Shape) | Tail] ->
        ( unit(Op, D) ->
            ( A = dim(0,0,0) -> Result = next([q(D,no,Shape)])
            ; Result = bad("Attach a unit only to a dimensionless value.") )
        ; Op = "array" ->
            ( same(Tail,A) -> Result = next([q(A,no,[list.length(Args)|Shape])])
            ; Result = bad("All array elements must have the same units.") )
        ; list.member(Op,["add","sub","sum","mean","median","min","max","mod","hypot","stdev"]) ->
            ( same(Tail,A) -> Result = next([q(A,no,Shape)])
            ; Result = bad("Incompatible units: addition, subtraction and summaries require matching dimensions.") )
        ; list.member(Op,["mul","dot","matmul","div"]), Tail = [q(B,_,_)] ->
            ( Op = "div" -> D = add(A,scale(B,-1)) ; D = add(A,B) ),
            Result = next([q(D,no,Shape)])
        ; Op = "pow", Tail = [q(B,Power,_)] ->
            ( B \= dim(0,0,0) -> Result = bad("An exponent must be dimensionless.")
            ; A = dim(0,0,0) -> Result = next([q(A,no,Shape)])
            ; Power = yes(N), N >= -32, N =< 32 -> Result = next([q(scale(A,N),no,Shape)])
            ; Result = bad("A quantity with units needs a literal integer exponent from -32 to 32.") )
        ; Op = "recip" -> Result = next([q(scale(A,-1),no,Shape)])
        ; Op = "variance" ->
            ( same(Tail,A) -> Result = next([q(scale(A,2),no,Shape)])
            ; Result = bad("Incompatible units: variance requires matching dimensions.") )
        ; Op = "det", Shape = [N,_] -> Result = next([q(scale(A,N),no,[])])
        ; list.member(Op,["sqrt","cbrt"]) ->
            ( Op = "sqrt" -> N = 2 ; N = 3 ),
            root_dim(A,N,Result)
        ; Op = "root", Tail = [q(dim(0,0,0),yes(N),_)] -> root_dim(A,N,Result)
        ; list.member(Op,["neg","abs","floor","ceil","round","percent","transpose","norm"]) ->
            ( Op = "neg", V = yes(N) -> NewV = yes(-N) ; NewV = no ),
            Result = next([q(A,NewV,Shape)])
        ; same(Args,dim(0,0,0)) -> Result = next([q(dim(0,0,0),no,Shape)])
        ; Result = bad(Op ++ " requires dimensionless arguments.")
        )
    ; Result = bad("An operation needs operands.")
    ).

:- pred root_dim(dim::in, int::in, step::out) is det.
root_dim(dim(L,M,T), N, Result) :-
    ( N \= 0, L mod N = 0, M mod N = 0, T mod N = 0 ->
        Result = next([q(dim(L // N,M // N,T // N),no,[])])
    ; Result = bad("This root would produce fractional unit exponents.")
    ).

:- func term(string, int) = string.
term(Name,N) = (if N = 0 then "" else if N = 1 then Name else Name ++ "^" ++ string.int_to_string(N)).
:- func label(dim) = string.
label(dim(L,M,T)) = string.join_list(" ", list.filter((pred(S::in) is semidet :- S \= ""), [term("m",L),term("kg",M),term("s",T)])).
